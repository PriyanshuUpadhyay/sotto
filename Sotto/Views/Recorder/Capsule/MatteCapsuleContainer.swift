import SwiftUI

// MARK: - MatteCapsuleContainer
//
// Live host for `MatteCapsuleView` (P2.4) — the stateful wrapper that derives
// `CapsuleState` from the engine and feeds the pure capsule view. Replaces
// `ConstellationCluster` as the recorder root; mirrors its phase derivation so
// the two TERMINAL states keep their existing, verified signals:
//
//   • `.commit` ← `stateProvider.lastPasteEvent` (1.2s dwell + fade), the same
//     PasteEvent-freshness window `ConstellationCluster` used.
//   • `.fail`   ← `FailureRegistry.$current` (the consolidated failure event).
//   • idle/recording/processing ← `RecordingState` via `CapsuleState.init`.
//
// `RecorderUIManager.phase` is NOT read here: it isn't injected under the mini
// window manager, and deriving commit/fail locally keeps the capsule working
// identically under both panels (mini + notch).

struct MatteCapsuleContainer<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    // De-observed (perf): forwarded only, never read — matches the
    // ConstellationCluster contract so `audioMeter`'s ~60Hz publish doesn't
    // churn this body.
    let recorder: Recorder

    @EnvironmentObject var failureRegistry: FailureRegistry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("failedDwellSeconds") private var failedDwellSeconds: Double = 6.0

    @State private var activeFailure: FailureEvent? = nil
    @State private var doneVisible: Bool = false
    @State private var doneTask: Task<Void, Never>? = nil
    @State private var failedTask: Task<Void, Never>? = nil
    @State private var recordingStartedAt: Date? = nil

    var body: some View {
        let state = derivedState

        // ONE always-mounted TimelineView so the capsule keeps a single
        // structural identity across recording→processing — a branch switch
        // here would recreate the capsule and reseed its reveal state,
        // snapping (not animating) the stop collapse. `.distantFuture`
        // effectively pauses the schedule outside recording (renders once,
        // never ticks); `elapsed` falls back to 0 when no start date.
        TimelineView(.periodic(from: recordingStartedAt ?? .distantFuture, by: 1.0)) { ctx in
            capsule(state: state,
                    elapsed: recordingStartedAt.map {
                        max(0, ctx.date.timeIntervalSince($0))
                    } ?? 0)
        }
        .padding(.bottom, MiniRecorderPanel.dockSafeBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onChange(of: stateProvider.recordingState) { _, newState in
            handleRecordingStateChange(newState)
        }
        .onChange(of: stateProvider.lastPasteEvent) { _, event in
            handlePasteEvent(event)
        }
        .onReceive(failureRegistry.$current) { event in
            handleFailureEvent(event)
        }
        .onAppear { handleRecordingStateChange(stateProvider.recordingState) }
    }

    private func capsule(state: CapsuleState, elapsed: TimeInterval) -> some View {
        MatteCapsuleView(
            state: state,
            elapsed: elapsed,
            // Full cumulative partial — the capsule's WordStream suffix-diffs
            // it and shows a fixed recency window; trimming here would break
            // the prefix-stability the diff relies on.
            partial: stateProvider.partialTranscript,
            warming: state == .processing && stateProvider.isWarmingUp,
            enhancing: stateProvider.recordingState == .enhancing,
            reduceMotion: reduceMotion,
            failure: activeFailure.map(RecorderUIManager.errorCode(from:)),
            onRetry: handleRetry,
            onOpenSettings: handleOpenSettings
        )
    }

    // MARK: - State derivation (done > failed > engine)

    private var derivedState: CapsuleState {
        if doneVisible { return .commit }
        if activeFailure != nil { return .fail }
        return CapsuleState(recordingState: stateProvider.recordingState)
    }

    private func handleRecordingStateChange(_ state: RecordingState) {
        switch state {
        case .starting, .recording:
            if recordingStartedAt == nil { recordingStartedAt = .now }
        default:
            recordingStartedAt = nil
        }
    }

    private func handlePasteEvent(_ event: PasteEvent?) {
        guard event != nil else { return }
        doneTask?.cancel()
        doneVisible = true
        doneTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Motion.commitHold))
            guard !Task.isCancelled else { return }
            doneVisible = false
        }
    }

    private func handleFailureEvent(_ event: FailureEvent?) {
        failedTask?.cancel()
        activeFailure = event
        guard let event else { return }
        let dwell = failedDwellSeconds
        guard dwell.isFinite else { return }
        let bounded = max(0.5, dwell)
        failedTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(bounded * 1000)))
            guard !Task.isCancelled else { return }
            failureRegistry.acknowledge(event.id)
        }
    }

    /// ⌘R retry chip — ack the surfaced failure, then re-arm via the same engine
    /// path the hotkey uses (`RecorderUIManager` observes `.retryRecording`).
    private func handleRetry() {
        failedTask?.cancel()
        failureRegistry.acknowledgeCurrent()
        NotificationCenter.default.post(name: .retryRecording, object: nil)
    }

    /// The `ERR · NO_MODEL` recovery — retrying without a model fails
    /// identically, so the chip sends the user where the fix is.
    private func handleOpenSettings() {
        failedTask?.cancel()
        failureRegistry.acknowledgeCurrent()
        SottoWindowCoordinator.shared.open(settingsTab: .models)
    }
}
