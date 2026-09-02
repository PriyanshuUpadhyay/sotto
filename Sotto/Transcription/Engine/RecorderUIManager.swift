import Foundation
import SwiftUI
import Combine
import os

@MainActor
class RecorderUIManager: ObservableObject {
    @Published var miniRecorderError: String?

    // MARK: - Halo phase observable

    @Published var phase: HaloPhase = .hidden
    @Published var recordingStartedAt: Date?
    @Published var formattedActivePromptLabel: String?
    @Published var currentErrorCode: FailureCode?
    @Published var lastPasteAppName: String?

    private var phaseObservers = Set<AnyCancellable>()
    private var doneHoldTask: Task<Void, Never>?
    private var armingHoldTask: Task<Void, Never>?

    /// True while the panel is being kept on screen for the post-paste
    /// ReviewTray even though the logical session has already ended
    /// (`isMiniRecorderVisible` is false so the next hotkey starts a fresh
    /// recording). It (a) suppresses the `isMiniRecorderVisible` didSet
    /// panel-hide and (b) lengthens the done-hold to the review window. The
    /// hold timer's expiry — or a superseding recording — clears it.
    /// Published so `MiniRecorderShortcutManager` keeps ESC active across the
    /// review window (ESC #2 closes the lingering capsule).
    @Published var isReviewWindowActive = false

    /// The post-paste edit-review tray — its own independent floating panel.
    let reviewTrayWindowManager = ReviewTrayWindowManager()

    @Published var isMiniRecorderVisible = false {
        didSet {
            if isMiniRecorderVisible {
                // A fresh session reclaims the panel — drop any review hold so
                // the hold timer can't tear the panel down mid-recording.
                isReviewWindowActive = false
                showRecorderPanel()
            } else if !isReviewWindowActive {
                hideRecorderPanel()
            }
        }
    }

    var miniWindowManager: MiniWindowManager?

    private weak var engine: SottoEngine?
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

    /// Call after SottoEngine + FailureRegistry are created to break the
    /// circular init dependency.
    func configure(engine: SottoEngine, recorder: Recorder, failureRegistry: FailureRegistry) {
        self.engine = engine
        self.recorder = recorder
        self.failureRegistry = failureRegistry
        reviewTrayWindowManager.configure(engine: engine, modelContext: engine.modelContext)
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
                    SottoFeedback.play(.fail)
                }
            }
            .store(in: &stateCueObservers)
    }

    // MARK: - Halo phase mapping

    private func setupPhaseObservers(engine: SottoEngine, registry: FailureRegistry) {
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
                // Float the independent post-paste tray over the lingering
                // capsule — but ONLY when review-before-paste is off. In review
                // mode the user already reviewed/edited in the compose editor
                // before this paste, so a second box would be redundant.
                let reviewOn = UserDefaults.standard.object(forKey: "ReviewBeforePaste") as? Bool ?? true
                if !reviewOn {
                    self?.reviewTrayWindowManager.present(event)
                }
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
                let interactive = Self.isInteractive(new)
                self?.miniWindowManager?.setIgnoresMouseEvents(!interactive)
            }
            .store(in: &phaseObservers)
    }

    /// Phases whose chips carry tappable controls (RETRY / OPEN SETTINGS) or
    /// otherwise warrant hit-testing. Outside these the panel stays
    /// click-through so menu-bar / app clicks fall through the full-width strip.
    private static func isInteractive(_ phase: HaloPhase) -> Bool {
        phase == .recording || phase == .liveText || phase == .done || phase == .failed
    }

    private func mapEngineState(_ state: RecordingState, engine: SottoEngine) {
        if state == .starting && phase == .done {
            doneHoldTask?.cancel()
            // A new recording supersedes the review window: the panel is already
            // on screen, so re-arming continues showing it (no hide/flash).
            isReviewWindowActive = false
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

        formattedActivePromptLabel = engine.enhancementService?.isEnhancementEnabled == true
            ? Self.formatPromptLabel(PredefinedPrompts.defaultPrompt.title)
            : nil
    }

    /// Re-evaluates the `.armed → .recording` promotion. Both gate conditions
    /// — first audio observed (`FirstAudioGate`, spec §4.2) and the
    /// `MotionTokens.armingHold` dwell — typically become true *after* the
    /// engine's lone `.recording` state publish, so this runs from the
    /// `firstAudioGate.$observed` observer and a follow-up timer, not only
    /// from `mapEngineState`. Idempotent — safe to call spuriously.
    private func evaluateRecordingPhase(engine: SottoEngine) {
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
        // When the panel is being kept up for the post-paste ReviewTray, hold
        // for the (longer) review window so the tray is usable; otherwise the
        // brief committed dwell.
        let hold = isReviewWindowActive ? MotionTokens.reviewWindowHold : MotionTokens.committedHold
        doneHoldTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled, let self else { return }
            if self.phase == .done {
                self.phase = .hidden
                self.lastPasteAppName = nil
                // Review window elapsed without a superseding recording — tear
                // the panel down now (`isMiniRecorderVisible` is already false).
                if self.isReviewWindowActive {
                    self.isReviewWindowActive = false
                    self.hideRecorderPanel()
                }
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

    /// Terse cause shown in place of "failed" on the fail capsule, plus
    /// whether retrying can help: without a model, a retry fails identically,
    /// so that case must offer Settings instead of ⌘R.
    enum FailureCode: String {
        case noModel  = "ERR · NO_MODEL"
        case noDevice = "ERR · NO_DEVICE"
        case network  = "ERR · NETWORK"
        case noAudio  = "ERR · NO_AUDIO"
        case unknown  = "ERR · UNKNOWN"

        var isRetryable: Bool { self != .noModel }
    }

    static func errorCode(from event: FailureEvent) -> FailureCode {
        let r = event.reason.uppercased()
        if r.contains("MODEL")          { return .noModel }
        if r.contains("DEVICE") || r.contains("MIC") { return .noDevice }
        if r.contains("NETWORK")        { return .network }
        if r.contains("AUDIO")          { return .noAudio }
        return .unknown
    }

    func dismissFailedPhase() {
        guard phase == .failed else { return }
        failureRegistry?.acknowledgeCurrent()
    }

    /// ESC #2 — end the post-paste review window NOW (the tray is already
    /// closed): cancel the done-hold, drop the review flag, and tear the
    /// lingering capsule/HUD down immediately. No-op outside the review window.
    func endReviewWindowNow() {
        guard isReviewWindowActive else { return }
        doneHoldTask?.cancel()
        isReviewWindowActive = false
        if phase == .done { phase = .hidden }
        lastPasteAppName = nil
        hideRecorderPanel()
    }

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
