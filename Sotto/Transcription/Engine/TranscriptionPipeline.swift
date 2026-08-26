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
    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "TranscriptionPipeline")

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
    ///   - dictationGeneration: The dictation generation captured ONCE by the
    ///     caller when THIS run began (`SottoEngine.runPipeline`'s entry) —
    ///     stamped on this run's own paste (`performPaste`) regardless of how
    ///     long that paste is deferred (review-before-paste can defer it
    ///     arbitrarily) or whether a newer dictation starts in the meantime.
    ///   - onStateChange: Called when the pipeline moves to a new recording state (e.g. `.enhancing`).
    ///   - onFailure: Called with a user-readable reason when the pipeline hits a failure path
    ///     (transcription throw or enhancement throw). The engine forwards this to
    ///     `failurePublisher` so the FailureRegistry can surface it.
    ///   - shouldCancel: Returns true if the user requested cancellation.
    ///   - onCleanup: Called when cancellation is detected to release model resources.
    ///   - onPreviewShown: Called right after the review-before-paste editor is
    ///     on screen (never on the direct-paste path) — the engine logs the
    ///     stop→preview-shown telemetry span from it.
    ///   - onDismiss: Called at the end to dismiss the recorder panel. The Bool
    ///     is true when a successful paste landed — the caller keeps the panel
    ///     on screen for the post-paste ReviewTray instead of hiding it at once.
    func run(
        transcription: Transcription,
        audioURL: URL,
        model: any TranscriptionModel,
        session: TranscriptionSession?,
        dictationGeneration: Int,
        onStateChange: @escaping (RecordingState) -> Void,
        onFailure: @escaping (String) -> Void,
        shouldCancel: () -> Bool,
        onCleanup: @escaping () async -> Void,
        onPreviewShown: @escaping () -> Void,
        onDismiss: @escaping (_ keepForReview: Bool) async -> Void
    ) async {
        if shouldCancel() {
            await onCleanup()
            return
        }

        var finalPastedText: String?
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
        var didInsertSessionMetric = false

        // Review-before-paste: when enabled, show the proposed text in an
        // editable preview and paste on the user's ⌘↵ instead of auto-pasting.
        // Never waits on the AI: if enhancement runs, the panel is presented
        // IMMEDIATELY at transcription-complete with the raw text editable,
        // and the enhanced result is delivered into the live panel when it
        // lands (dropped if the user already committed/cancelled).
        let reviewEnabled = UserDefaults.standard.object(forKey: "ReviewBeforePaste") as? Bool ?? true
        // True once the review editor has been presented; the editor then owns
        // the paste (on ⌘↵) and the surface, so the tail skips the post-paste
        // ReviewTray and starts auto-vocab monitoring there.
        var presentedComposeReview = false
        var reviewSession: Int?

        // Shared ⌘↵ handler for both present sites. `enhancedRef` is whatever
        // enhanced text the panel had actually received by commit time — nil
        // when the user pasted ahead of a pending (or absent) enhancement, in
        // which case there is no exact edit signal to record.
        let reviewCommitHandler: (String, String?, Bool) -> Void = { [weak self] finalText, enhancedRef, fromRawLineage in
            guard let self else { return }
            self.performPaste(pasteText: finalText, dictationGeneration: dictationGeneration)
            // Auto-vocab AX monitoring starts only after the paste lands in
            // the real target field.
            AutoLearnVocabularyService.shared.beginMonitoring()
            // Exact edit signal: final vs enhanced. EditSignalService
            // self-handles a no-op (final == enhanced). Read the target app
            // AFTER performPaste so lastPasteContext is the real field.
            // `transcription.promptName` is read here (not captured at present
            // time) — on the early-present path it is only set once
            // enhancement succeeds, which is also what makes enhancedRef non-nil.
            if let enhancedRef {
                // CorrectionMiner mines `.edit` as enhanced→final. When the
                // committed text descends from the RAW face (raw toggle, or
                // edits made before the enhancement landed), enhanced was
                // never the base: verbatim raw → `.revertRaw`; edited raw →
                // record NOTHING (there is no valid enhanced→final pair, and
                // a wrong triplet is worse than a missing one).
                let source: EditSignalSource? = fromRawLineage
                    ? (finalText == transcription.text ? .revertRaw : nil)
                    : .edit
                if let source {
                    let bundleID = CursorPaster.lastPasteContext?.targetApp?.bundleIdentifier
                    EditSignalService().record(
                        rawText: transcription.text,
                        enhancedText: enhancedRef,
                        finalText: finalText,
                        source: source,
                        appBundleID: bundleID,
                        transcriptionID: transcription.id,
                        promptName: transcription.promptName,
                        in: self.modelContext
                    )
                }
            }
        }

        logger.notice("🔄 Starting transcription...")

        // Per-utterance observability. Populated unconditionally (negligible
        // cost, single code path); emitted once at the end only when the
        // PipelineTraceLoggingEnabled debug flag is set.
        var trace = TranscriptionTrace()
        let audioMetrics = await Self.audioMetrics(for: audioURL)
        trace.audioDurationSeconds = audioMetrics.durationSeconds
        trace.audioSampleCount = audioMetrics.sampleCount

        do {
            let transcriptionStart = Date()
            var text: String
            let asrStart = TranscriptionTrace.now()
            if let session {
                text = try await session.transcribe(audioURL: audioURL, audioDurationSeconds: audioMetrics.durationSeconds)
                trace.sessionType = session.diagnostics.sessionType
                trace.streamingFinalLength = session.diagnostics.streamingFinalLength
                trace.fallbackReason = session.diagnostics.fallbackReason ?? ""
            } else {
                trace.sessionType = "batch"
                text = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
            }
            trace.record(.asr, since: asrStart)
            logger.notice("📝 Transcript: \(text, privacy: .public)")
            trace.asrText = text
            trace.asrModel = model.displayName
            // M2 in-decoder rescore is FluidAudio-only and runs inside the
            // service actor; read its per-utterance outcome here. Realtime
            // (streaming) runs reset it to nil, so this is null for the M1 path.
            if model.provider == .fluidAudio {
                let boostingStart = TranscriptionTrace.now()
                trace.boosting = await serviceRegistry.fluidAudioTranscriptionService.lastBoosting
                trace.record(.boosting, since: boostingStart)
            }
            let filterStart = TranscriptionTrace.now()
            text = TranscriptionOutputFilter.filter(text)
            trace.record(.filter, since: filterStart)
            logger.notice("📝 Output filter result: \(text, privacy: .public)")
            trace.afterFilter = text
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

            if shouldCancel() { await onCleanup(); return }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if UserDefaults.standard.bool(forKey: "IsTextFormattingEnabled") {
                text = WhisperTextFormatter.format(text)
                logger.notice("📝 Formatted transcript: \(text, privacy: .public)")
            }

            let wordReplaceStart = TranscriptionTrace.now()
            text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
            trace.record(.wordReplacement, since: wordReplaceStart)
            logger.notice("📝 WordReplacement: \(text, privacy: .public)")
            trace.afterWordReplace = text

            // Acoustic confirmation: CTC spotter reports which vocab terms it
            // thinks were spoken. Evidence from the realtime path showed it
            // over-confirming the entire vocabulary (21/21 kept on ordinary
            // utterances), which made the homophone unlock rewrite valid words
            // ("to"→"TUI", "then"→"Thine"). When explicitly enabled we still log
            // the spotter output for diagnostics, but we do not apply it below.
            // Re-enable by passing the confirmed set only after the spotter's
            // scores actually discriminate.
            var acousticallyConfirmed: Set<String>? = nil
            if AcousticBoostingPolicy.isEnabled(forModelNamed: model.name) {
                let terms = (try? modelContext.fetch(FetchDescriptor<VocabularyWord>()))?.map { $0.word } ?? []
                if !terms.isEmpty {
                    let acousticStart = TranscriptionTrace.now()
                    let details = await AcousticVocabularyService.shared.confirmedTermsDetailed(at: audioURL, terms: terms)
                    trace.record(.acoustic, since: acousticStart)
                    trace.acoustic = details
                    acousticallyConfirmed = Set(details.filter { $0.kept }.map { $0.term })
                    logger.notice("🎙️ AcousticConfirm: \(acousticallyConfirmed?.sorted().joined(separator: ",") ?? "-", privacy: .public)")
                }
            }

            // Evidence mode: do NOT apply the homophone-unlock (pass nil), but
            // keep the spotter's confirmations in trace.acoustic above.
            let phoneticStart = TranscriptionTrace.now()
            let phoneticResult = PhoneticCorrectionService.shared.correctDetailed(text, using: modelContext, acousticallyConfirmed: nil)
            trace.record(.phonetic, since: phoneticStart)
            text = phoneticResult.text
            trace.phonetic = phoneticResult.corrections
            trace.afterPhonetic = text
            logger.notice("📝 PhoneticCorrect: \(text, privacy: .public)")

            let actualDuration = audioMetrics.durationSeconds ?? 0.0

            transcription.text = text
            transcription.duration = actualDuration
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            finalPastedText = text

            let isSkipShortEnhancementEnabled = UserDefaults.standard.bool(forKey: "SkipShortEnhancement")
            let savedThreshold = UserDefaults.standard.integer(forKey: "ShortEnhancementWordThreshold")
            let shortEnhancementWordThreshold = savedThreshold > 0 ? savedThreshold : 3
            let shouldSkipEnhancement = isSkipShortEnhancementEnabled && WordCounter.count(in: text) <= shortEnhancementWordThreshold

            if let enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured,
               !shouldSkipEnhancement {
                if shouldCancel() { await onCleanup(); return }

                let textForAI = text

                // Optionally skip the LLM when the raw transcript is already
                // clean (~66% of runs were no-ops costing ~1.7s median). Default
                // is now OFF — the stronger Light pass is meant to punctuate and
                // fix grammar on every dictation, not only messy ones; skipping
                // clean-looking Parakeet output muted it. Set the key true to
                // restore the latency-saving skip.
                let skipWhenClean = UserDefaults.standard.object(forKey: "SkipEnhancementWhenClean") as? Bool ?? false
                if skipWhenClean,
                   EnhancementSanityCheck.isLikelyClean(textForAI) {
                    logger.notice("🦾 enhance: skipped (raw already clean)")
                } else {
                    // P3.F: transcribe-complete cue fires "ASR finishes, before
                    // enhance" per spec §3.10. The enhance step then runs (often
                    // several seconds), and enhance-complete fires before paste.
                    SoundManager.shared.playTranscribeComplete()
                    didFireTranscribeCue = true

                    onStateChange(.enhancing)

                    // Never wait on the AI: the review editor appears NOW with
                    // the raw transcript editable; ⌘↵ pastes the current text
                    // immediately and the pending enhancement is dropped on
                    // delivery.
                    if reviewEnabled {
                        presentedComposeReview = true
                        reviewSession = ComposeReviewWindowManager.shared.present(
                            rawText: textForAI,
                            enhancedText: nil,
                            isEnhancing: true,
                            onCommit: reviewCommitHandler
                        )
                        onPreviewShown()
                    }

                    do {
                        let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(textForAI)
                        logger.notice("📝 AI enhancement: \(enhancedText, privacy: .public)")
                        transcription.enhancedText = enhancedText
                        transcription.aiEnhancementModelName = enhancementService.lastEnhancementModelUsed
                        transcription.promptName = promptName
                        transcription.enhancementDuration = enhancementDuration
                        trace.record(.enhancement, seconds: enhancementDuration)
                        transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                        transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                        finalPastedText = enhancedText
                        didEnhance = true
                        trace.afmModel = enhancementService.lastEnhancementModelUsed ?? ""
                        trace.afmEdits = WordDiffEngine.findSingleWordSubstitutions(original: textForAI, edited: enhancedText)
                            .map { TranscriptionTrace.WordEdit(from: $0.original, to: $0.replacement) }
                        trace.afterEnhance = enhancedText
                        if let reviewSession,
                           ComposeReviewWindowManager.shared.deliverEnhanced(enhancedText, session: reviewSession) {
                            // "Done" cue at the moment the enhanced text lands
                            // in the live panel (the pre-paste cue below never
                            // runs on the review path). Skipped when the user
                            // already committed/cancelled — the paste happened.
                            SoundManager.shared.playEnhanceComplete()
                        }
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
                        // Clear the panel's ENHANCING state (raw stays editable).
                        // false = the panel was already committed/cancelled — the
                        // user pasted and moved on, so suppress the failure
                        // notification + visual along with the dropped delivery
                        // (the log line above still records it). No review
                        // session (review off) surfaces normally.
                        let surfaceFailure = reviewSession.map {
                            ComposeReviewWindowManager.shared.deliverEnhanced(nil, session: $0)
                        } ?? true
                        if surfaceFailure {
                            // A guardrail refusal is not a malfunction — the
                            // transcript still pastes, just un-enhanced. Say
                            // that plainly instead of "Enhancement failed:
                            // <raw provider string>", and say it regardless of
                            // the failure-notification pref: a silently
                            // declined dictation is exactly the case the user
                            // has no other signal for.
                            let isRefusal = (error as? EnhancementError).map {
                                if case .safetyRefusal = $0 { return true } else { return false }
                            } ?? false
                            if isRefusal {
                                // Fire-and-forget, NOT `await MainActor.run`:
                                // showNotification builds a hosting controller
                                // and an NSPanel synchronously, so awaiting it
                                // parks the raw transcript behind whatever else
                                // the main actor is doing. The toast is
                                // advisory; the paste is not.
                                Task { @MainActor in
                                    NotificationManager.shared.showNotification(
                                        title: "Enhancement declined — pasted raw transcript",
                                        type: .warning,
                                        duration: 2.5
                                    )
                                }
                            } else if UserDefaults.standard.bool(forKey: "EnableEnhancementFailureNotification") {
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
                        }
                        if shouldCancel() {
                            if presentedComposeReview { ComposeReviewWindowManager.shared.cancel() }
                            await onCleanup()
                            return
                        }
                    }
                }
            }

            transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue
            // SessionMetric lives in the separate stats.store container, not the
            // transcript context — write it through a fresh stats context and
            // save THAT (the transcript save below persists the Transcription).
            if let statsContainer = StatsModelContainerProvider.shared.modelContainer {
                do {
                    let statsContext = ModelContext(statsContainer)
                    didInsertSessionMetric = try SessionMetricRecorder.recordRecorderSession(
                        transcription: transcription,
                        model: model,
                        in: statsContext
                    )
                    if didInsertSessionMetric {
                        try statsContext.save()
                    }
                } catch {
                    logger.error("Failed to record session metric: \(error.localizedDescription, privacy: .public)")
                }
            }

            if UserDefaults.standard.object(forKey: "PipelineTraceLoggingEnabled") as? Bool ?? true {
                let rendered = trace.render()
                logger.notice("🔎 Trace:\n\(rendered, privacy: .public)")
                TranscriptionTraceLog.shared.append(rendered)
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

        if shouldCancel() {
            if presentedComposeReview { ComposeReviewWindowManager.shared.cancel() }
            await onCleanup()
            return
        }

        if let textToPaste = finalPastedText,
           transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue,
           !presentedComposeReview {

            let pasteText = textToPaste

            if reviewEnabled {
                // Enhancement never ran (disabled / skipped / short) — present
                // the editor now with the single available text. When it DID
                // run, the panel went up at enhance-start above and this tail
                // is skipped.
                presentedComposeReview = true

                // "Done" cue now — processing is complete and the editor appears
                // (mirrors the pre-paste cue on the auto-paste path below).
                if didEnhance {
                    SoundManager.shared.playEnhanceComplete()
                } else if !didFireTranscribeCue {
                    SoundManager.shared.playTranscribeComplete()
                }

                ComposeReviewWindowManager.shared.present(
                    rawText: transcription.text,
                    enhancedText: didEnhance ? pasteText : nil,
                    isEnhancing: false,
                    onCommit: reviewCommitHandler
                )
                onPreviewShown()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
                    guard let self else { return }
                    // P3.F: pre-paste cue. enhance-complete if enhancement
                    // actually ran (slightly softer stacked arpeggio), else
                    // transcribe-complete (the fundamental "done" cue) — but only
                    // if the pre-enhance transcribe cue didn't already fire
                    // (enhance-failure path) so we don't stack three cues.
                    if didEnhance {
                        SoundManager.shared.playEnhanceComplete()
                    } else if !didFireTranscribeCue {
                        SoundManager.shared.playTranscribeComplete()
                    }
                    self.performPaste(pasteText: pasteText, dictationGeneration: dictationGeneration)
                }
            }
        }

        // When the review editor is up it replaces the post-paste tray and
        // owns the surface — dismiss the recorder immediately (no keep-for-
        // review) and let the editor's ⌘↵ start monitoring after the paste.
        // Otherwise keep the panel up for the post-paste ReviewTray only when
        // a paste actually landed (completed run with text). Failure / empty
        // tails hide it immediately as before.
        let keepForReview = !presentedComposeReview
            && finalPastedText != nil
            && transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue
        await onDismiss(keepForReview)

        // Start only after the recorder is fully dismissed — avoids racing
        // focus changes from our own UI (mirrors the wiring removed in
        // 00ee007). In the review path the editor's ⌘↵ starts monitoring instead.
        if !presentedComposeReview {
            AutoLearnVocabularyService.shared.beginMonitoring()
        }
    }

    /// The shared paste sequence — auto-vocab focus capture → Cmd+V. Called by
    /// the auto-paste path (review OFF) and by the review editor's ⌘↵ commit
    /// (review ON). The "done" cue is played by the caller, since the moment it
    /// marks (processing-complete vs about-to-paste) differs by path.
    ///
    /// `dictationGeneration` is `run(...)`'s own captured-at-start value, NOT
    /// a fresh read of `enhancementService?.dictationGeneration` — this call
    /// can be deferred an arbitrary, user-controlled amount of time (the
    /// review-before-paste editor), during which a NEWER dictation can start
    /// and bump the shared counter. Stamping THIS run's own generation (fixed
    /// at run-start, never re-read) is what lets `SottoEngine.
    /// handleDidPaste` attribute stop→paste telemetry to the run that
    /// actually produced this paste, not whichever dictation happens to be
    /// current when the deferred paste finally fires.
    private func performPaste(pasteText: String, dictationGeneration: Int) {
        let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
        let textToInsert = pasteText + (appendSpace ? " " : "")

        // Auto-vocabulary: capture the destination field while it still has
        // focus, before Cmd+V fires, so finalize() can diff single-word
        // corrections into Vocabulary.
        let autoLearn = AutoLearnVocabularyService.shared
        if let element = autoLearn.captureFocusedElement() {
            autoLearn.prepareMonitoring(pastedText: textToInsert, element: element, modelContext: self.modelContext)
        }

        CursorPaster.pasteAtCursor(textToInsert, dictationGeneration: dictationGeneration)
    }

    private static func audioMetrics(for url: URL) async -> (durationSeconds: Double?, sampleCount: Int?) {
        if let audioFile = try? AVAudioFile(forReading: url) {
            let sampleRate = audioFile.fileFormat.sampleRate
            let sampleCount = Int(audioFile.length)
            let duration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : nil
            return (duration, sampleCount)
        }

        let audioAsset = AVURLAsset(url: url)
        let duration = (try? CMTimeGetSeconds(await audioAsset.load(.duration))).flatMap { value in
            value.isFinite ? value : nil
        }
        return (duration, nil)
    }
}
