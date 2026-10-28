import Foundation
import AVFoundation
import SwiftData
import os

/// Handles the full post-recording pipeline:
/// transcribe → filter → format → word-replace → prompt-detect → AI enhance → save → paste → dismiss
@MainActor
class TranscriptionPipeline {
    let modelContext: ModelContext
    let serviceRegistry: TranscriptionServiceRegistry
    let enhancementService: AIEnhancementService?
    let logger = Logger(subsystem: OSLogSubsystems.app, category: "TranscriptionPipeline")

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

        let reviewCommitHandler = makeReviewCommitHandler(transcription: transcription, dictationGeneration: dictationGeneration)

        logger.notice("🔄 Starting transcription...")

        // Per-utterance observability. Populated unconditionally (negligible
        // cost, single code path); emitted once at the end only when the
        // PipelineTraceLoggingEnabled debug flag is set.
        var trace = TranscriptionTrace()
        let audioMetrics = await Self.audioMetrics(for: audioURL)
        trace.audioDurationSeconds = audioMetrics.durationSeconds
        trace.audioSampleCount = audioMetrics.sampleCount

        do {
            let transcribed = try await transcribeAudio(audioURL: audioURL, model: model, session: session, audioMetrics: audioMetrics, trace: &trace)
            var text = transcribed.text
            let transcriptionDuration = transcribed.transcriptionDuration

            if shouldCancel() { await onCleanup(); return }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            text = await cleanTranscript(text, audioURL: audioURL, model: model, trace: &trace)

            let actualDuration = audioMetrics.durationSeconds ?? 0.0

            transcription.text = text
            transcription.duration = actualDuration
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            finalPastedText = text

            if await enhanceTranscript(
                text: text,
                transcription: transcription,
                reviewEnabled: reviewEnabled,
                reviewCommitHandler: reviewCommitHandler,
                onStateChange: onStateChange,
                onFailure: onFailure,
                shouldCancel: shouldCancel,
                onCleanup: onCleanup,
                onPreviewShown: onPreviewShown,
                finalPastedText: &finalPastedText,
                didEnhance: &didEnhance,
                didFireTranscribeCue: &didFireTranscribeCue,
                presentedComposeReview: &presentedComposeReview,
                reviewSession: &reviewSession,
                trace: &trace
            ) { return }

            transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue
            recordSessionMetric(transcription: transcription, model: model, didInsertSessionMetric: &didInsertSessionMetric)

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

        presentOrPasteTranscript(
            finalPastedText: finalPastedText,
            transcription: transcription,
            presentedComposeReview: &presentedComposeReview,
            reviewEnabled: reviewEnabled,
            didEnhance: didEnhance,
            didFireTranscribeCue: didFireTranscribeCue,
            dictationGeneration: dictationGeneration,
            reviewCommitHandler: reviewCommitHandler,
            onPreviewShown: onPreviewShown
        )

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
    func performPaste(pasteText: String, dictationGeneration: Int) {
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
