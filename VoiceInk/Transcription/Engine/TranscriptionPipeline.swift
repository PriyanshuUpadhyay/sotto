import Foundation
import AVFoundation
import SwiftData
import os

/// Handles the full post-recording pipeline:
/// transcribe → filter → format → word-replace → prompt-detect → AI enhance → save → paste → dismiss
@MainActor
class TranscriptionPipeline {
    private let modelContext: ModelContext
    private let serviceRegistry: TranscriptionServiceRegistry
    private let enhancementService: AIEnhancementService?
    private let promptDetectionService = PromptDetectionService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionPipeline")

    init(
        modelContext: ModelContext,
        serviceRegistry: TranscriptionServiceRegistry,
        enhancementService: AIEnhancementService?
    ) {
        self.modelContext = modelContext
        self.serviceRegistry = serviceRegistry
        self.enhancementService = enhancementService
    }

    /// Run the full pipeline for a given transcription record.
    /// - Parameters:
    ///   - transcription: The pending Transcription SwiftData object to populate and save.
    ///   - audioURL: The recorded audio file.
    ///   - model: The transcription model to use.
    ///   - session: An active streaming session if one was prepared, otherwise nil.
    ///   - onStateChange: Called when the pipeline moves to a new recording state (e.g. `.enhancing`).
    ///   - onFailure: Called with a user-readable reason when the pipeline hits a failure path
    ///     (transcription throw or enhancement throw). The engine forwards this to
    ///     `failurePublisher` so the FailureRegistry can surface it.
    ///   - shouldCancel: Returns true if the user requested cancellation.
    ///   - onCleanup: Called when cancellation is detected to release model resources.
    ///   - onDismiss: Called at the end to dismiss the recorder panel.
    func run(
        transcription: Transcription,
        audioURL: URL,
        model: any TranscriptionModel,
        session: TranscriptionSession?,
        onStateChange: @escaping (RecordingState) -> Void,
        onFailure: @escaping (String) -> Void,
        shouldCancel: () -> Bool,
        onCleanup: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void
    ) async {
        if shouldCancel() {
            await onCleanup()
            return
        }

        var finalPastedText: String?
        var promptDetectionResult: PromptDetectionService.PromptDetectionResult?
        // P3.F: hoisted out of the do-block so the post-do asyncAfter closure
        // (which picks the pre-paste cue) can read it. Flipped only on
        // successful enhance.
        var didEnhance = false
        // Polish: also hoist a "did the pre-enhance transcribe cue already
        // fire?" flag. On enhance-failure, the engine state flip fires `playFail`
        // via the Combine sink in `RecorderUIManager`; without this guard the
        // pre-paste asyncAfter would replay `playTranscribeComplete`, stacking
        // three cues (transcribe → fail → transcribe). Skip the pre-paste
        // transcribe cue when the pre-enhance one already fired.
        var didFireTranscribeCue = false

        logger.notice("🔄 Starting transcription...")

        do {
            let transcriptionStart = Date()
            var text: String
            if let session {
                text = try await session.transcribe(audioURL: audioURL)
            } else {
                text = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
            }
            logger.notice("📝 Transcript: \(text, privacy: .public)")
            text = TranscriptionOutputFilter.filter(text)
            logger.notice("📝 Output filter result: \(text, privacy: .public)")
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

            let powerModeManager = PowerModeManager.shared
            let activePowerModeConfig = powerModeManager.currentActiveConfiguration
            let powerModeName = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.name : nil
            let powerModeEmoji = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.emoji : nil

            if shouldCancel() { await onCleanup(); return }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if UserDefaults.standard.bool(forKey: "IsTextFormattingEnabled") {
                text = WhisperTextFormatter.format(text)
                logger.notice("📝 Formatted transcript: \(text, privacy: .public)")
            }

            text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
            logger.notice("📝 WordReplacement: \(text, privacy: .public)")

            // W12.C: pre-enhance snippet expansion. No-op when the snippet
            // table is empty. Service caches the active list in memory; the
            // cache invalidates on every CRUD action via `invalidateCache()`.
            // See plan `docs/superpowers/plans/W12C-voice-snippets.md`
            // §Migration policy #2.
            let snippetResult = SnippetExpansionService.shared.expand(
                text: text,
                modelContext: modelContext
            )
            if snippetResult.expandedCount > 0 {
                text = snippetResult.expanded
                logger.notice("🦾 snippets: expanded \(snippetResult.expandedCount, privacy: .public) triggers")
                if UserDefaults.standard.bool(forKey: "DebugLogSnippetExpansion") {
                    logger.notice("📝 Snippet expansion: \(text, privacy: .public)")
                }
            }

            let audioAsset = AVURLAsset(url: audioURL)
            let actualDuration = (try? CMTimeGetSeconds(await audioAsset.load(.duration))) ?? 0.0

            transcription.text = text
            transcription.duration = actualDuration
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            transcription.powerModeName = powerModeName
            transcription.powerModeEmoji = powerModeEmoji
            finalPastedText = text

            if let enhancementService, enhancementService.isConfigured {
                let detectionResult = await promptDetectionService.analyzeText(text, with: enhancementService)
                promptDetectionResult = detectionResult
                await promptDetectionService.applyDetectionResult(detectionResult, to: enhancementService)
            }

            let isSkipShortEnhancementEnabled = UserDefaults.standard.bool(forKey: "SkipShortEnhancement")
            let savedThreshold = UserDefaults.standard.integer(forKey: "ShortEnhancementWordThreshold")
            let shortEnhancementWordThreshold = savedThreshold > 0 ? savedThreshold : 3
            let shouldSkipEnhancement = isSkipShortEnhancementEnabled && WordCounter.count(in: text) <= shortEnhancementWordThreshold && !(promptDetectionResult?.shouldEnableAI == true)

            if let enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured,
               !shouldSkipEnhancement {
                if shouldCancel() { await onCleanup(); return }

                // P3.F: transcribe-complete cue fires "ASR finishes, before
                // enhance" per spec §3.10. The enhance step then runs (often
                // several seconds), and enhance-complete fires before paste.
                SoundManager.shared.playTranscribeComplete()
                didFireTranscribeCue = true

                onStateChange(.enhancing)
                let textForAI = promptDetectionResult?.processedText ?? text

                do {
                    let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(textForAI)
                    logger.notice("📝 AI enhancement: \(enhancedText, privacy: .public)")
                    transcription.enhancedText = enhancedText
                    transcription.aiEnhancementModelName = enhancementService.getAIService()?.currentModel
                    transcription.promptName = promptName
                    transcription.enhancementDuration = enhancementDuration
                    transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                    transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                    finalPastedText = enhancedText
                    didEnhance = true
                } catch {
                    let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    let shortReason = String(errorDescription.prefix(80))
                    // Don't write the error into `transcription.enhancedText` —
                    // history views and the copy/paste path resolve text via
                    // `enhancedText ?? text`, so persisting a failure string
                    // there leaks "Enhancement failed: …" into the clipboard
                    // and the history list. Leaving it nil falls through to
                    // the raw transcript everywhere.
                    logger.error("AI enhancement failed: \(errorDescription, privacy: .public)")
                    await MainActor.run {
                        NotificationManager.shared.showNotification(
                            title: "Enhancement failed: \(shortReason)",
                            type: .warning
                        )
                    }
                    // Surface to engine so the failure visual can render. Paste
                    // still proceeds with the un-enhanced transcript (silent fallback).
                    onFailure("Enhancement failed: \(shortReason)")
                    if shouldCancel() { await onCleanup(); return }
                }
            }

            transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue

        } catch {
            let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let recoverySuggestion = (error as? LocalizedError)?.recoverySuggestion ?? ""
            let fullErrorText = recoverySuggestion.isEmpty ? errorDescription : "\(errorDescription) \(recoverySuggestion)"

            transcription.text = "Transcription Failed: \(fullErrorText)"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
            // Surface to engine so the failure visual can render during dwell.
            let shortReason = String(errorDescription.prefix(80))
            onFailure("Transcription failed: \(shortReason)")
        }

        try? modelContext.save()
        NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)

        if shouldCancel() { await onCleanup(); return }

        if let textToPaste = finalPastedText,
           transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
                // P3.F: pre-paste cue. enhance-complete if enhancement actually
                // ran (slightly softer stacked arpeggio), else transcribe-
                // complete (the fundamental "done" cue) — but only if the
                // pre-enhance transcribe cue didn't already fire (enhance-
                // failure path) so we don't stack three cues.
                if didEnhance {
                    SoundManager.shared.playEnhanceComplete()
                } else if !didFireTranscribeCue {
                    SoundManager.shared.playTranscribeComplete()
                }
                let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
                CursorPaster.pasteAtCursor(textToPaste + (appendSpace ? " " : ""))

                let powerMode = PowerModeManager.shared
                if let activeConfig = powerMode.currentActiveConfiguration, activeConfig.autoSendKey.isEnabled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        CursorPaster.performAutoSend(activeConfig.autoSendKey)
                    }
                }
            }
        }

        if let result = promptDetectionResult,
           let enhancementService,
           result.shouldEnableAI {
            await promptDetectionService.restoreOriginalSettings(result, to: enhancementService)
        }

        await onDismiss()
    }
}
