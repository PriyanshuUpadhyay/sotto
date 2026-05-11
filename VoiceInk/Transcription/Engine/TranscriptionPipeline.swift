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
        // W12.B — captured at the fork so the post-paste auto-send block
        // (which fires after CommandModeService.clear() flips pendingCommand
        // to nil) can still distinguish command-mode rewrites. Policy #14:
        // a rewrite is the final state — never auto-Enter into Slack/etc.
        var wasCommandMode = false
        var didInsertSessionMetric = false

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

            // W12.B — Command Mode fork. When CommandModeService.shared.pendingCommand
            // is non-nil, the user pressed Caps+9 before this recording started,
            // the selection was captured, and the dictated text is the rewrite
            // instruction. Bypass prompt-detection (Migration policy #4) and
            // the standard enhance gate; route through commandModeRewrite(...)
            // and paste the rewrite in place of the selection.
            if let pending = CommandModeService.shared.pendingCommand,
               let enhancementService {
                wasCommandMode = true
                if shouldCancel() { CommandModeService.shared.clear(); await onCleanup(); return }

                // Mirror the standard pre-enhance cue (§3.10). Rewrite latency
                // is a few seconds on MLX; the cue acknowledges the dictation
                // landed before the rewrite finishes.
                SoundManager.shared.playTranscribeComplete()
                didFireTranscribeCue = true

                onStateChange(.enhancing)
                let rewriteStart = Date()

                do {
                    let rewrite = try await CommandModeService.shared.processInstruction(transcript: text)
                    logger.notice("🦾 command-mode: rewrite produced (\(rewrite.count, privacy: .public) chars)")
                    transcription.enhancedText = rewrite
                    transcription.aiEnhancementModelName = enhancementService.getAIService()?.currentModel
                    transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                    transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                    transcription.enhancementDuration = Date().timeIntervalSince(rewriteStart)
                    transcription.commandModeSelection = pending.selectionText
                    transcription.commandModeInstruction = text
                    finalPastedText = rewrite
                    didEnhance = true
                } catch {
                    let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    let shortReason = String(errorDescription.prefix(80))
                    logger.error("🦾 command-mode: rewrite failed — \(errorDescription, privacy: .public)")
                    await MainActor.run {
                        NotificationManager.shared.showNotification(
                            title: "Command Mode rewrite failed: \(shortReason)",
                            type: .warning
                        )
                    }
                    // Migration policy #12 — fall-through bypass: do NOT paste
                    // anything. The user's selection stays intact; they can
                    // re-press Caps+9 to retry.
                    finalPastedText = nil
                    onFailure("Command Mode rewrite failed: \(shortReason)")
                }

                CommandModeService.shared.clear()
            } else {
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
                        if UserDefaults.standard.bool(forKey: "EnableEnhancementFailureNotification") {
                            await MainActor.run {
                                NotificationManager.shared.showNotification(
                                    title: "Enhancement failed: \(shortReason)",
                                    type: .warning
                                )
                            }
                        }
                        // Surface to engine so the failure visual can render. Paste
                        // still proceeds with the un-enhanced transcript (silent fallback).
                        onFailure("Enhancement failed: \(shortReason)")
                        if shouldCancel() { await onCleanup(); return }
                    }
                }
            }

            transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue
            do {
                didInsertSessionMetric = try SessionMetricRecorder.recordRecorderSession(
                    transcription: transcription,
                    model: model,
                    in: modelContext
                )
            } catch {
                logger.error("Failed to record session metric: \(error.localizedDescription, privacy: .public)")
            }

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

        do {
            try modelContext.save()
            if didInsertSessionMetric {
                NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
            }
            NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)
        } catch {
            logger.error("Failed to save transcription: \(error.localizedDescription, privacy: .public)")
        }

        if shouldCancel() { await onCleanup(); return }

        if let textToPaste = finalPastedText,
           transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {

            // W12.D: hands-free voice-trigger detection. Runs only when a
            // hands-free session is active; returns nil otherwise. Hands-free
            // inactive → identical paste behavior as pre-W12.D (Migration #2).
            let isHandsFreeActive = HandsFreeSessionService.shared.state != .inactive
            let triggerHit: VoiceTriggerFilter.TriggerHit? = isHandsFreeActive
                ? VoiceTriggerFilter.detectTrigger(
                    in: textToPaste,
                    against: HandsFreeSessionService.shared.mode.triggerPhrases
                  )
                : nil
            let pasteText = triggerHit?.cleanedText ?? textToPaste

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
                let textToInsert = pasteText + (appendSpace ? " " : "")

                // W12.E dictation-into-place: when the Scratchpad is the key
                // window AND a tab editor holds first-responder, route the
                // transcript into the active tab at cursor position. Suppresses
                // auto-send (no unwanted ⏎ inside the Scratchpad). First
                // decision point — mutually exclusive with the paste-fallback
                // branch (Migration policy #12 / #13).
                if ScratchpadWindowController.shared.isFocusedAndKey {
                    ScratchpadWindowController.shared.insertIntoActiveTab(textToInsert)
                    return
                }

                CursorPaster.pasteAtCursor(textToInsert)

                // W12.B — gate auto-send on standard-recorder origin only.
                // Command Mode rewrites are final; an auto-Enter would send the
                // rewrite as a Slack/etc message. Policy #14 / Risks #14.
                // W12.D Migration #8: voice trigger overrides PowerMode autoSend
                // so a "press enter" utterance fires Enter exactly once.
                if !wasCommandMode {
                    if let hit = triggerHit {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            CursorPaster.performAutoSend(hit.autoSend)
                        }
                    } else {
                        let powerMode = PowerModeManager.shared
                        if let activeConfig = powerMode.currentActiveConfiguration, activeConfig.autoSendKey.isEnabled {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                CursorPaster.performAutoSend(activeConfig.autoSendKey)
                            }
                        }
                    }
                }
            }
        }

        if let result = promptDetectionResult,
           let enhancementService,
           result.shouldEnableAI {
            await promptDetectionService.restoreOriginalSettings(result, to: enhancementService)
        }

        // W12.D: skip the pipeline-tail dismiss while a hands-free session is
        // active. Dismiss would hide the recorder panel + release model
        // resources between utterances, which breaks re-arm. The session
        // service runs `dismissMiniRecorder()` once at session end instead.
        if HandsFreeSessionService.shared.state == .inactive {
            await onDismiss()
        }
    }
}
