import Foundation
import SwiftUI
import Combine
import os

@MainActor
class RecorderUIManager: ObservableObject {
    @Published var miniRecorderError: String?

    // MARK: - Bay HUD phase observable

    @Published var phase: HaloPhase = .hidden
    @Published var recordingStartedAt: Date?
    @Published var formattedActivePromptLabel: String?
    @Published var currentErrorCode: String?
    @Published var lastPasteAppName: String?

    private var phaseObservers = Set<AnyCancellable>()
    private var doneHoldTask: Task<Void, Never>?
    private var armingHoldTask: Task<Void, Never>?

    @Published var recorderType: String = {
        // Legacy "constellation" value (shipped briefly as a vaporware tile
        // that fell through to mini) → migrate to "mini" on read.
        let stored = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini"
        return stored == "constellation" ? "mini" : stored
    }() {
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

    /// Failure cue (`SoundManager.playFail`) fires on each registry publish,
    /// not on engine state. Held strongly because the registry's lifetime
    /// matches the app process. Set via `configure(...)` once the registry
    /// is built.
    private var failureRegistry: FailureRegistry?

    /// Combine subscription to `FailureRegistry.$current` that fires the
    /// failure cue (`SoundManager.playFail`) on every fresh failure event.
    /// Stored as a set so the sink is torn down with the manager.
    private var stateCueObservers = Set<AnyCancellable>()

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "RecorderUIManager")

    init() {}

    /// Call after VoiceInkEngine + FailureRegistry are created to break the
    /// circular init dependency.
    func configure(engine: VoiceInkEngine, recorder: Recorder, failureRegistry: FailureRegistry) {
        self.engine = engine
        self.recorder = recorder
        self.failureRegistry = failureRegistry
        setupNotifications()
        setupFailureCueObserver(registry: failureRegistry)
        setupPhaseObservers(engine: engine, registry: failureRegistry)
    }

    /// Fire `SoundManager.playFail` on every fresh `FailureEvent` published
    /// by the registry. Failures originate from multiple engine sites
    /// (recorder start, missing model, transcription throw, enhancement
    /// throw) — the registry consolidates them so the cue trigger lives in
    /// one place.
    private func setupFailureCueObserver(registry: FailureRegistry) {
        stateCueObservers.removeAll()

        registry.$current
            .compactMap { $0 }
            .removeDuplicates()
            .sink { _ in
                Task { @MainActor in
                    SoundManager.shared.playFail()
                }
            }
            .store(in: &stateCueObservers)
    }

    // MARK: - Bay HUD phase mapping

    private func setupPhaseObservers(engine: VoiceInkEngine, registry: FailureRegistry) {
        engine.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.mapEngineState(state, engine: engine)
            }
            .store(in: &phaseObservers)

        // The `.armed → .recording` gate (first audio + arming hold) only
        // becomes satisfiable *after* the engine's single `.recording` state
        // publish, so re-evaluate it each time the first-audio gate latches.
        engine.firstAudioGate.$observed
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak engine] _ in
                guard let self, let engine else { return }
                self.evaluateRecordingPhase(engine: engine)
            }
            .store(in: &phaseObservers)

        registry.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                if let event {
                    self.currentErrorCode = Self.errorCode(from: event)
                    self.phase = .failed
                } else if self.phase == .failed {
                    self.phase = .hidden
                    self.currentErrorCode = nil
                }
            }
            .store(in: &phaseObservers)

        engine.$lastPasteEvent
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.beginDoneHold(appName: event.appName)
            }
            .store(in: &phaseObservers)

        $phase
            .removeDuplicates()
            .sink { [weak self] new in
                self?.logger.notice("phase → \(String(describing: new), privacy: .public)")
            }
            .store(in: &phaseObservers)

        $phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] new in
                let interactive = (new == .recording || new == .liveText || new == .done || new == .failed)
                self?.notchWindowManager?.setIgnoresMouseEvents(!interactive)
            }
            .store(in: &phaseObservers)
    }

    private func mapEngineState(_ state: RecordingState, engine: VoiceInkEngine) {
        if state == .starting && phase == .done {
            doneHoldTask?.cancel()
            phase = .hidden
            lastPasteAppName = nil
        }

        if phase == .done || phase == .failed { return }

        switch state {
        case .idle, .busy:
            armingHoldTask?.cancel()
            phase = .hidden
            recordingStartedAt = nil
        case .starting:
            phase = .armed
            if recordingStartedAt == nil { recordingStartedAt = .now }
        case .recording:
            if recordingStartedAt == nil { recordingStartedAt = .now }
            phase = .armed
            evaluateRecordingPhase(engine: engine)
        case .transcribing:
            phase = .transcribing
        case .enhancing:
            phase = .enhancing
        }

        formattedActivePromptLabel = Self.formatPromptLabel(
            engine.enhancementService?.activePrompt?.title
        )
    }

    /// Re-evaluates the `.armed → .recording` promotion. Both gate conditions
    /// — first audio observed (`FirstAudioGate`, spec §4.2) and the
    /// `MotionTokens.armingHold` dwell — typically become true *after* the
    /// engine's lone `.recording` state publish, so this runs from the
    /// `firstAudioGate.$observed` observer and a follow-up timer, not only
    /// from `mapEngineState`. Idempotent — safe to call spuriously.
    private func evaluateRecordingPhase(engine: VoiceInkEngine) {
        guard engine.recordingState == .recording, phase == .armed,
              engine.firstAudioObserved,
              let started = recordingStartedAt else { return }

        armingHoldTask?.cancel()
        let elapsed = Date().timeIntervalSince(started)
        if elapsed >= MotionTokens.armingHold {
            phase = .recording
        } else {
            // First audio beat the arming hold — wait out the remainder.
            armingHoldTask = Task { @MainActor [weak self, weak engine] in
                try? await Task.sleep(for: .seconds(MotionTokens.armingHold - elapsed))
                guard !Task.isCancelled, let self, let engine else { return }
                self.evaluateRecordingPhase(engine: engine)
            }
        }
    }

    private func beginDoneHold(appName: String?) {
        doneHoldTask?.cancel()
        lastPasteAppName = appName
        phase = .done
        doneHoldTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(MotionTokens.committedHold))
            guard !Task.isCancelled, let self else { return }
            if self.phase == .done {
                self.phase = .hidden
                self.lastPasteAppName = nil
            }
        }
    }

    private static func formatPromptLabel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let upper = raw.uppercased()
        if upper.count <= 9 { return upper }
        let idx = upper.index(upper.startIndex, offsetBy: 9)
        return String(upper[..<idx])
    }

    private static func errorCode(from event: FailureEvent) -> String {
        let r = event.reason.uppercased()
        if r.contains("MODEL")          { return "ERR · NO_MODEL" }
        if r.contains("DEVICE") || r.contains("MIC") { return "ERR · NO_DEVICE" }
        if r.contains("NETWORK")        { return "ERR · NETWORK" }
        if r.contains("AUDIO")          { return "ERR · NO_AUDIO" }
        return "ERR · UNKNOWN"
    }

    func dismissFailedPhase() {
        guard phase == .failed else { return }
        failureRegistry?.acknowledgeCurrent()
    }

    // MARK: - Recorder Panel Management

    func showRecorderPanel() {
        guard let engine = engine,
              let recorder = recorder,
              let failureRegistry = failureRegistry else { return }
        logger.notice("Showing \(self.recorderType, privacy: .public) recorder")

        if recorderType == "notch" {
            if notchWindowManager == nil {
                notchWindowManager = NotchWindowManager(engine: engine, recorder: recorder, failureRegistry: failureRegistry, uiManager: self)
            }
            notchWindowManager?.show()
        } else {
            if miniWindowManager == nil {
                miniWindowManager = MiniWindowManager(engine: engine, recorder: recorder, failureRegistry: failureRegistry)
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

        // W12.B — defensive command-mode teardown. The pipeline calls clear()
        // on success or rewrite failure; this catches the cancel-mid-dictation
        // + Escape-mid-dictation paths. Idempotent.
        CommandModeService.shared.clear()

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
