import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import Combine
import os

extension SottoEngine {
    // MARK: - Hands-free commit (W12.D)

    /// W12.D hands-free commit: stop the current recording, run the pipeline
    /// for the captured utterance, then optionally start a new recording so
    /// the next utterance can begin immediately. Each utterance is its own
    /// `Transcription` row (matches existing schema).
    ///
    /// - Parameter restartAfter: `true` (hands-free in progress) → re-arm the
    ///   recorder for the next utterance. `false` (session ending or one-shot
    ///   drain) → leave the recorder stopped.
    ///
    /// This method calls `toggleRecord` directly (rather than tearing the
    /// recorder panel down) so the panel stays visible across utterance commits.
    func commitUtterance(restartAfter: Bool = true) async {
        guard recordingState == .recording else {
            logger.notice("🦾 hands-free: commitUtterance skipped — state=\(String(describing: self.recordingState), privacy: .public)")
            return
        }
        logger.notice("🦾 hands-free: commitUtterance restartAfter=\(restartAfter, privacy: .public)")

        // Stop + run pipeline via the existing toggleRecord flow.
        await toggleRecord()

        guard restartAfter else { return }

        // Wait for recordingState to settle to .idle. The pipeline tail in
        // runPipeline sets recordingState back to .idle at `:292-294`. Use a
        // bounded spin-wait so a slow pipeline doesn't permanently block the
        // hands-free session.
        var spins = 0
        while recordingState != .idle, spins < 100 {
            try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms
            spins += 1
        }
        guard recordingState == .idle else {
            logger.error("🦾 hands-free: commitUtterance abort — recordingState=\(String(describing: self.recordingState), privacy: .public) after pipeline spin-wait")
            return
        }
        // Re-arm.
        await toggleRecord()
    }

    // MARK: - Pipeline Dispatch

    func runPipeline(on transcription: Transcription, audioURL: URL) async {
        failurePublishedDuringRun = false

        guard let model = transcriptionModelManager.currentTranscriptionModel else {
            transcription.text = "Transcription Failed: No model selected"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
            try? modelContext.save()
            failurePublisher.send(FailureEvent(reason: "No transcription model selected"))
            failurePublishedDuringRun = true
            recordingState = .idle
            return
        }

        let session = currentSession
        currentSession = nil

        // Captured ONCE here — when THIS run begins — not re-read at paste
        // time. A review-before-paste editor can defer this run's own paste
        // by an arbitrary amount; a NEW dictation can start (bumping the
        // shared `dictationGeneration`) in that window. Reading fresh at
        // paste time would then stamp this run's paste with the NEWER
        // dictation's generation instead of its own, letting it wrongly
        // match that newer dictation's (possibly still-uncleared) stop
        // timestamp. Passed straight through to `TranscriptionPipeline.run`,
        // which threads it into every `performPaste` call unchanged.
        let dictationGeneration = enhancementService?.dictationGeneration ?? 0

        await pipeline.run(
            transcription: transcription,
            audioURL: audioURL,
            model: model,
            session: session,
            dictationGeneration: dictationGeneration,
            onStateChange: { [weak self] state in self?.recordingState = state },
            onFailure: { [weak self] reason in
                guard let self else { return }
                // Generation-scoped like the teardown below: a stale run must
                // not publish failure UI — or set the shared
                // `failurePublishedDuringRun` flag — while a newer dictation
                // is active.
                guard (self.enhancementService?.dictationGeneration ?? 0) == dictationGeneration else {
                    self.logger.notice("onFailure skipped – newer dictation active")
                    return
                }
                // NOT a no-paste terminal: transcription-failure IS terminal,
                // but enhancement-failure falls through and still pastes the
                // raw transcript (TranscriptionPipeline.run's catch block
                // continues to its paste tail instead of returning) — clearing
                // `lastStopTimestamp` here would drop stop→paste telemetry on
                // every raw-fallback run. The paste token match in
                // `handleDidPaste` already prevents any false attribution.
                self.failurePublisher.send(FailureEvent(reason: reason))
                self.failurePublishedDuringRun = true
            },
            shouldCancel: { [weak self] in self?.shouldCancelRecording ?? false },
            onCleanup: { [weak self] in
                // Pipeline aborted early via `shouldCancel()` — same reasoning
                // as `onFailure`: this run will never paste.
                self?.lastStopTimestamp = nil
                await self?.releaseResourcesAfterDictation()
            },
            onPreviewShown: { [weak self] in
                // Stop→preview-shown span: stop → review panel on screen. When
                // enhancement runs, the panel presents at enhance-START (raw
                // editable), so the span covers transcribe + UI present only —
                // enhancement lands into the already-visible panel. Same stop +
                // generation match as `handleDidPaste`, but does NOT consume
                // `lastStopTimestamp` — the preview precedes the paste, and the
                // paste span still needs it.
                guard let self, let stopInfo = self.lastStopTimestamp,
                      stopInfo.generation == dictationGeneration else { return }
                let elapsed = Date().timeIntervalSince(stopInfo.date)
                Task { await EnhancementTimingLogger.shared.recordStopToPreview(seconds: elapsed) }
            },
            onDismiss: { [weak self] keepForReview in
                guard let self else { return }
                // Generation-scoped: this pipeline's tail can now run while a
                // NEWER dictation is already recording (the review editor pastes
                // mid-enhance and the user re-records; `beginNewDictation` bumped
                // the shared counter). Tearing down then would stop the new
                // recording's session and hide its UI.
                guard (self.enhancementService?.dictationGeneration ?? 0) == dictationGeneration else {
                    self.logger.notice("onDismiss skipped – newer dictation active")
                    return
                }
                await self.recorderUIManager?.dismissMiniRecorder(deferWindowHideForReview: keepForReview)
            }
        )

        // Same generation scope as `onDismiss`: don't reset a newer dictation's
        // cancel flag or flip its `.recording` state back to `.idle`.
        guard (enhancementService?.dictationGeneration ?? 0) == dictationGeneration else {
            logger.notice("runPipeline tail skipped – newer dictation active")
            return
        }

        shouldCancelRecording = false
        if recordingState != .idle {
            recordingState = .idle
        }
        // Clean-run ack: a pipeline that reached the tail without `onFailure`
        // firing observed a successful end-to-end run, so any unresolved
        // failure from a prior run is now stale. Skip the clear when the
        // current run itself published a failure — otherwise we'd wipe the
        // registry one frame after surfacing the very failure we just
        // published, and the cluster + menubar dot would never see it.
        if !failurePublishedDuringRun {
            failureRegistry.clearAll()
        }
    }
}
