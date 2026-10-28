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

    var phaseObservers = Set<AnyCancellable>()
    var doneHoldTask: Task<Void, Never>?
    var armingHoldTask: Task<Void, Never>?

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

    weak var engine: SottoEngine?
    var recorder: Recorder?

    /// Failure cue (`SoundManager.playFail`) fires on each registry publish,
    /// not on engine state. Held strongly because the registry's lifetime
    /// matches the app process. Set via `configure(...)` once the registry
    /// is built.
    var failureRegistry: FailureRegistry?

    /// Combine subscription to `FailureRegistry.$current` that fires the
    /// failure cue (`SoundManager.playFail`) on every fresh failure event.
    /// Stored as a set so the sink is torn down with the manager.
    private var stateCueObservers = Set<AnyCancellable>()

    let logger = Logger(subsystem: OSLogSubsystems.app, category: "RecorderUIManager")

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

}
