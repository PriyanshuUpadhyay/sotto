import Foundation
import SwiftUI
import Combine
import os

@MainActor
class RecorderUIManager: ObservableObject {
    @Published var miniRecorderError: String?

    @Published var recorderType: String = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini" {
        didSet {
            if isMiniRecorderVisible {
                if oldValue == "notch" {
                    notchWindowManager?.destroyWindow()
                    notchWindowManager = nil
                } else {
                    miniWindowManager?.destroyWindow()
                    miniWindowManager = nil
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    showRecorderPanel()
                }
            }
            UserDefaults.standard.set(recorderType, forKey: "RecorderType")
        }
    }

    @Published var isMiniRecorderVisible = false {
        didSet {
            if isMiniRecorderVisible {
                showRecorderPanel()
            } else {
                hideRecorderPanel()
            }
        }
    }

    var notchWindowManager: NotchWindowManager?
    var miniWindowManager: MiniWindowManager?

    private weak var engine: VoiceInkEngine?
    private var recorder: Recorder?

    /// P3.F: Combine subscription to engine.recordingState for the failure cue.
    /// Stored here so it's torn down with the manager (engine is weak — sink
    /// holds a strong-self closure capture, so we must keep this owned by us
    /// to break the cycle on dealloc).
    private var stateCueObservers = Set<AnyCancellable>()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "RecorderUIManager")

    init() {}

    /// Call after VoiceInkEngine is created to break the circular init dependency.
    func configure(engine: VoiceInkEngine, recorder: Recorder) {
        self.engine = engine
        self.recorder = recorder
        setupNotifications()
        setupStateCueObservers(engine: engine)
    }

    /// P3.F: Fire the synthesized failure cue whenever the engine transitions
    /// into `.failed`. Failures originate from multiple sites (recorder start,
    /// missing model, transcription throw, enhancement throw) — observing the
    /// state directly keeps the cue trigger consolidated rather than scattering
    /// `playFail()` calls across each error path.
    private func setupStateCueObservers(engine: VoiceInkEngine) {
        engine.$recordingState
            .removeDuplicates()
            .sink { newState in
                guard case .failed = newState else { return }
                Task { @MainActor in
                    SoundManager.shared.playFail()
                }
            }
            .store(in: &stateCueObservers)
    }

    // MARK: - Recorder Panel Management

    func showRecorderPanel() {
        guard let engine = engine, let recorder = recorder else { return }
        logger.notice("Showing \(self.recorderType, privacy: .public) recorder")

        if recorderType == "notch" {
            if notchWindowManager == nil {
                notchWindowManager = NotchWindowManager(engine: engine, recorder: recorder)
            }
            notchWindowManager?.show()
        } else {
            if miniWindowManager == nil {
                miniWindowManager = MiniWindowManager(engine: engine, recorder: recorder)
            }
            miniWindowManager?.show()
        }
    }

    func hideRecorderPanel() {
        if recorderType == "notch" {
            notchWindowManager?.hide()
        } else {
            miniWindowManager?.hide()
        }
    }

    // MARK: - Mini Recorder Management

    func toggleMiniRecorder(powerModeId: UUID? = nil) async {
        guard let engine = engine else { return }
        logger.notice("toggleMiniRecorder called – visible=\(self.isMiniRecorderVisible, privacy: .public), state=\(String(describing: engine.recordingState), privacy: .public)")

        if isMiniRecorderVisible {
            if engine.recordingState == .recording {
                logger.notice("toggleMiniRecorder: stopping recording (was recording)")
                await engine.toggleRecord(powerModeId: powerModeId)
            } else {
                logger.notice("toggleMiniRecorder: cancelling (was not recording)")
                await cancelRecording()
            }
        } else {
            SoundManager.shared.playStartSound {
                Task { await MediaController.shared.muteSystemAudio() }
            }
            await MainActor.run { isMiniRecorderVisible = true }
            await engine.toggleRecord(powerModeId: powerModeId)
        }
    }

    func dismissMiniRecorder() async {
        guard let engine = engine, let recorder = recorder else { return }
        logger.notice("dismissMiniRecorder called – state=\(String(describing: engine.recordingState), privacy: .public)")

        // Hold off teardown while the engine is dwelling on `.failed` so the
        // failure visual gets its window before the panel collapses. The dwell
        // is bounded by `VoiceInkEngine.failedDwellSeconds`; loop exits cleanly
        // whether the engine self-collapses to `.idle` or a new recording starts.
        while case .failed = engine.recordingState {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if engine.recordingState == .busy {
            logger.notice("dismissMiniRecorder: early return, state is busy")
            return
        }

        let wasRecording = engine.recordingState == .recording

        await MainActor.run {
            engine.recordingState = .busy
        }

        // Cancel and release any active streaming session to prevent resource leaks.
        engine.currentSession?.cancel()
        engine.currentSession = nil

        if wasRecording {
            await recorder.stopRecording()
        }

        hideRecorderPanel()

        // Clear captured context when the recorder is dismissed
        if let enhancementService = engine.enhancementService {
            await MainActor.run {
                enhancementService.clearCapturedContexts()
            }
        }

        await MainActor.run {
            isMiniRecorderVisible = false
        }

        await engine.cleanupResources()

        if UserDefaults.standard.bool(forKey: PowerModeDefaults.autoRestoreKey) {
            await PowerModeSessionManager.shared.endSession()
            await MainActor.run {
                PowerModeManager.shared.setActiveConfiguration(nil)
            }
        }

        await MainActor.run {
            engine.recordingState = .idle
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
        await dismissMiniRecorder()
    }

    // MARK: - Notification Handling

    private func setupNotifications() {
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
}
