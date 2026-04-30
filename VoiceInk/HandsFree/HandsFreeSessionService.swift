import Foundation
import Combine
import AppKit
import os

/// W12.D hands-free session orchestrator. Single global instance; coordinates
/// recorder cycling, silence detection, the 20-min cap, and graceful drain.
/// All state mutation is `@MainActor`-confined.
///
/// Lead Q3: ~150-300ms audio gap between utterances acceptable v1 (file
/// rotation deferred). Lead Q5: hands-free toggle ENDS Command Mode if active
/// (W12.B). Lead Q6: 20-min hardcoded; no Settings exposure v1. Lead Q9: no
/// forced cleanup level — use whatever the user has globally.
@MainActor
final class HandsFreeSessionService: ObservableObject {
    static let shared = HandsFreeSessionService()

    @Published private(set) var state: HandsFreeSessionState = .inactive

    /// Snapshot of `HandsFreeMode` captured at session start. Mid-session
    /// settings tweaks (VAD threshold, silence duration, trigger phrases) do
    /// NOT apply to the live session — restart the session via the toggle
    /// hotkey to pick up changes. Plan-acceptable v1 (Migration policy #6).
    private(set) var mode: HandsFreeMode = .current()

    private weak var engine: VoiceInkEngine?
    private weak var recorderUIManager: RecorderUIManager?

    private let silenceDetector = SilenceDetector()
    private var meterCancellable: AnyCancellable?
    private var capTimerTask: Task<Void, Never>?
    private var commitTask: Task<Void, Never>?
    private var sleepObserver: NSObjectProtocol?

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink",
                                category: "HandsFreeSessionService")

    enum EndReason: String {
        case userToggle = "user-toggle"
        case sessionCap = "session-cap"
        case pipelineFailure = "pipeline-failure"
        case otherHotkey = "other-hotkey"
    }

    private init() {}

    // MARK: - Public API

    /// Toggle the session on or off. Called from the global hotkey handler.
    func toggle(engine: VoiceInkEngine, recorderUIManager: RecorderUIManager) async {
        if state == .inactive {
            await startSession(engine: engine, recorderUIManager: recorderUIManager)
        } else {
            await endSession(reason: .userToggle)
        }
    }

    // MARK: - Session lifecycle

    private func startSession(engine: VoiceInkEngine, recorderUIManager: RecorderUIManager) async {
        self.engine = engine
        self.recorderUIManager = recorderUIManager
        self.mode = .current()
        silenceDetector.configure(thresholdDb: mode.vadThresholdDb,
                                  silenceDuration: mode.silenceDuration)
        silenceDetector.reset()

        state = .listening
        logger.notice("🦾 hands-free: state=listening (start)")

        // Start recorder via the existing user-initiated path so the panel
        // shows + the start cue plays + media muting fires.
        await recorderUIManager.toggleMiniRecorder()

        // Subscribe to audio meter for silence detection. `Recorder.audioMeter`
        // is `@Published` on the main actor; the sink hops to main explicitly
        // so handleMeterSample is safe under the @MainActor isolation.
        meterCancellable = engine.recorder.$audioMeter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meter in
                guard let self = self else { return }
                Task { @MainActor in
                    self.handleMeterSample(meter)
                }
            }

        // 20-min session cap. Sleep is cancellable via Task.cancel() in
        // endSession, which throws CancellationError — swallowed by `try?`.
        capTimerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(20.0 * 60.0 * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.endSession(reason: .sessionCap)
        }

        // T9.5: end the session on system sleep so we don't resume into a
        // stale recorder state when the user wakes back up. NSWorkspace
        // notifications post on `NSWorkspace.shared.notificationCenter`, NOT
        // `NotificationCenter.default` — using the wrong center silently
        // never fires (codebase convention: see ModelPrewarmService,
        // AutoLearnVocabularyService, GlassAppearance, Animation+Halo).
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.endSession(reason: .pipelineFailure)
            }
        }
    }

    /// Graceful drain: cancels timers + meter subscription, flushes the
    /// in-flight utterance (if any), dismisses the recorder panel, and
    /// returns state to `.inactive`. Re-entrancy-safe.
    func endSession(reason: EndReason) async {
        guard state != .inactive, state != .endingSession else { return }
        state = .endingSession
        logger.notice("🦾 hands-free: state=endingSession reason=\(reason.rawValue, privacy: .public)")

        capTimerTask?.cancel(); capTimerTask = nil
        commitTask?.cancel(); commitTask = nil
        meterCancellable?.cancel(); meterCancellable = nil
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            sleepObserver = nil
        }

        // Drain in-flight: if recorder is still recording, fire one final
        // commit so the user's last utterance isn't dropped. If the pipeline
        // is mid-run already (.transcribing / .enhancing), let it finish so
        // its paste fires and resources aren't yanked while in use.
        if let engine = engine, engine.recordingState == .recording {
            await engine.commitUtterance(restartAfter: false)
        }

        // Wait for any in-flight pipeline (.transcribing / .enhancing) to
        // settle before tearing down. Bounded so a wedged pipeline can't
        // block teardown forever; 100×20ms = 2s ceiling.
        var spins = 0
        while let engine = engine, engine.recordingState != .idle, spins < 100 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            spins += 1
        }

        // Dismiss the recorder panel via the existing tail.
        await recorderUIManager?.dismissMiniRecorder()

        silenceDetector.reset()
        state = .inactive
        logger.notice("🦾 hands-free: state=inactive")

        if reason == .sessionCap {
            NotificationManager.shared.showNotification(
                title: "Hands-free session ended (20-min cap)",
                type: .info
            )
        }
    }

    // MARK: - Meter → silence → commit

    private func handleMeterSample(_ meter: AudioMeter) {
        guard state == .listening else { return }
        if silenceDetector.update(meter: meter, now: Date()) == .silenceDetected {
            commitTask?.cancel()
            commitTask = Task { [weak self] in
                await self?.commitCurrentUtterance()
            }
        }
    }

    private func commitCurrentUtterance() async {
        guard state == .listening, let engine = engine else { return }
        state = .committing
        logger.notice("🦾 hands-free: state=committing")

        await engine.commitUtterance()

        // After the new recorder is armed (or the spin-wait gave up).
        guard state == .committing else { return } // session ended mid-commit
        silenceDetector.reset()
        state = .listening
        logger.notice("🦾 hands-free: state=listening (post-commit)")
    }
}
