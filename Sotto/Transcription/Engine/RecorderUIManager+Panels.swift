import Foundation
import SwiftUI
import Combine
import os

extension RecorderUIManager {
    // MARK: - Recorder Panel Management

    func showRecorderPanel() {
        guard let engine = engine,
              let recorder = recorder,
              let failureRegistry = failureRegistry else { return }
        logger.notice("Showing Mini recorder")

        if miniWindowManager == nil {
            miniWindowManager = MiniWindowManager(engine: engine, recorder: recorder, failureRegistry: failureRegistry)
        }
        miniWindowManager?.show()
        // Sync hit-testing to the current phase so a panel that appears
        // already in an interactive phase (e.g. `.failed`) is clickable —
        // the $phase sink only fires on change, not on panel creation.
        miniWindowManager?.setIgnoresMouseEvents(!Self.isInteractive(phase))
    }

    func hideRecorderPanel() {
        miniWindowManager?.hide()
    }

    // MARK: - Mini Recorder Management

    func toggleMiniRecorder() async {
        guard let engine = engine else { return }
        logger.notice("toggleMiniRecorder called – visible=\(self.isMiniRecorderVisible, privacy: .public), state=\(String(describing: engine.recordingState), privacy: .public)")

        if isMiniRecorderVisible {
            if engine.recordingState == .recording {
                logger.notice("toggleMiniRecorder: stopping recording (was recording)")
                await engine.toggleRecord()
            } else if await MainActor.run(body: { ComposeReviewWindowManager.shared.isPresented }) {
                // A review panel is up mid-enhance — the dictation hotkey must
                // never silently discard user-visible text. Same semantics as
                // the fresh-start branch below: toggleRecord's start path
                // auto-commits (pastes) the panel, then records the next take.
                logger.notice("toggleMiniRecorder: committing review panel + starting next recording")
                SoundManager.shared.playStartSound {
                    Task { await MediaController.shared.muteSystemAudio() }
                }
                SottoFeedback.play(.arm)
                await engine.toggleRecord()
            } else {
                logger.notice("toggleMiniRecorder: cancelling (was not recording)")
                await cancelRecording()
            }
        } else {
            SoundManager.shared.playStartSound {
                Task { await MediaController.shared.muteSystemAudio() }
            }
            SottoFeedback.play(.arm)
            await MainActor.run { isMiniRecorderVisible = true }
            await engine.toggleRecord()
        }
    }

    /// - Parameter deferWindowHideForReview: When true (pipeline success path),
    ///   run the full logical teardown — release the session, cleanup, flip
    ///   the engine to `.idle` — but KEEP the panel on screen
    ///   so the post-paste ReviewTray is usable. `isMiniRecorderVisible` is
    ///   still set false so the next hotkey starts a fresh recording; the panel
    ///   is torn down by the review-hold timer (`beginDoneHold`) or a
    ///   superseding recording. Defaults to today's immediate-hide behavior so
    ///   cancel / failure / hands-free callers are unchanged.
    func dismissMiniRecorder(deferWindowHideForReview: Bool = false) async {
        guard let engine = engine, let recorder = recorder else { return }
        logger.notice("dismissMiniRecorder called – state=\(String(describing: engine.recordingState), privacy: .public), deferReview=\(deferWindowHideForReview, privacy: .public)")

        if engine.recordingState == .busy {
            logger.notice("dismissMiniRecorder: early return, state is busy")
            return
        }

        let wasRecording = engine.recordingState == .recording

        // Pin `.done` and arm the review hold BEFORE flipping engine state so
        // the imminent `.busy`/`.idle` publishes can't force the panel to
        // `.hidden` in the gap before the (15ms-delayed) paste event arrives —
        // `mapEngineState` early-returns while `phase == .done`.
        if deferWindowHideForReview {
            isReviewWindowActive = true
            phase = .done
        }

        await MainActor.run {
            engine.recordingState = .busy
        }

        // Cancel and release any active streaming session to prevent resource leaks.
        engine.currentSession?.cancel()
        engine.currentSession = nil

        if wasRecording {
            await recorder.stopRecording()
        }

        if !deferWindowHideForReview {
            hideRecorderPanel()
        }

        // Clear captured context when the recorder is dismissed
        if let enhancementService = engine.enhancementService {
            await MainActor.run {
                enhancementService.clearCapturedContexts()
            }
        }

        await MainActor.run {
            // didSet honors `isReviewWindowActive` — the panel stays up while the
            // hotkey gate sees the session as ended.
            isMiniRecorderVisible = false
        }

        await engine.releaseResourcesAfterDictation()

        await MainActor.run {
            engine.recordingState = .idle
        }

        // Arm the review-hold timer as a fallback so the kept panel always
        // tears down even if no paste event arrives (e.g. dictation routed
        // into the Scratchpad). The real `lastPasteEvent` re-arms it with the
        // destination app name.
        if deferWindowHideForReview {
            beginDoneHold(appName: lastPasteAppName)
        }

        logger.notice("dismissMiniRecorder completed")
    }

    func resetOnLaunch() async {
        guard let engine = engine, let recorder = recorder else { return }
        logger.notice("Resetting recording state on launch")
        await recorder.stopRecording()
        hideRecorderPanel()
        await MainActor.run {
            isMiniRecorderVisible = false
            engine.shouldCancelRecording = false
            miniRecorderError = nil
            engine.recordingState = .idle
        }
        await engine.cleanupResources()
    }

    func cancelRecording() async {
        guard let engine = engine else { return }
        logger.notice("cancelRecording called")
        SoundManager.shared.playEscSound()
        engine.shouldCancelRecording = true
        // A review-before-paste panel presented at enhance-start outlives the
        // recorder — the pipeline only re-checks shouldCancel at its next
        // checkpoint (post-enhance), so take the panel down here too. No-op
        // when nothing is presented.
        await MainActor.run { ComposeReviewWindowManager.shared.cancel() }
        await dismissMiniRecorder()
    }

    // MARK: - Notification Handling

    func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleMiniRecorder),
            name: .toggleMiniRecorder,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissMiniRecorder),
            name: .dismissMiniRecorder,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRetryRecording),
            name: .retryRecording,
            object: nil
        )
    }

    @objc public func handleToggleMiniRecorder() {
        logger.notice("handleToggleMiniRecorder: .toggleMiniRecorder notification received")
        Task {
            await toggleMiniRecorder()
        }
    }

    @objc public func handleDismissMiniRecorder() {
        logger.notice("handleDismissMiniRecorder: .dismissMiniRecorder notification received")
        Task {
            await dismissMiniRecorder()
        }
    }

    @objc public func handleRetryRecording() {
        logger.notice("handleRetryRecording: .retryRecording notification received")
        Task {
            await retryRecording()
        }
    }

    /// RETRY chip: re-arm the recorder after a surfaced failure. The cluster
    /// has already acknowledged the `FailureEvent`; here we start a fresh
    /// recording attempt via the same engine path a hotkey press would use.
    ///   • panel hidden        → show it and start (toggleMiniRecorder)
    ///   • panel visible + idle → start a fresh recording in place
    ///   • already capturing/processing → no-op (nothing to retry)
    func retryRecording() async {
        guard let engine = engine else { return }
        logger.notice("retryRecording – visible=\(self.isMiniRecorderVisible, privacy: .public), state=\(String(describing: engine.recordingState), privacy: .public)")

        if !isMiniRecorderVisible {
            await toggleMiniRecorder()
            return
        }

        switch engine.recordingState {
        case .idle, .starting:
            await engine.toggleRecord()
        default:
            // recording / transcribing / enhancing / busy — a run is already
            // in flight, so there is nothing to retry.
            break
        }
    }
}
