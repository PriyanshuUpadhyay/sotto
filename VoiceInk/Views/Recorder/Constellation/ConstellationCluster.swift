import SwiftUI
import AppKit

// MARK: - ConstellationCluster
//
// Orchestrator for the W2 chip cluster (spec §2 + §4). Owns:
//   • RecordingState → ClusterPhase derivation
//   • Done-dwell synthesis (1.2s + 0.24s fade) keyed off PasteEvent
//   • Failed-dwell timer (read AppStorage("failedDwellSeconds"), default 6s)
//   • W3 seam: injectFailure(reason:) — FailureRegistry will call this
//   • ChipPanel composition + accessibility wrapping
//
// Position: anchor centred horizontally below the notch (or virtual notch on
// non-notch displays), 50pt below the menu-bar baseline. Geometry computed
// via ConstellationLayout — host panel is full-screen-width × 120pt, click-
// through except on action chips.

struct ConstellationCluster<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    let mode: HaloShape.Mode

    @AppStorage("failedDwellSeconds") private var failedDwellSeconds: Double = 6.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Phase state

    @State private var injectedFailure: String? = nil
    @State private var donePayload: DonePayload? = nil
    @State private var doneFading: Bool = false
    @State private var doneTask: Task<Void, Never>? = nil
    @State private var failedTask: Task<Void, Never>? = nil
    @State private var recordingStartedAt: Date? = nil

    private struct DonePayload: Equatable {
        let appName: String?
        let preview: String?
    }

    // MARK: - Body

    var body: some View {
        let layout = ConstellationLayout.current(mode: mode)
        let phase = derivedPhase

        ZStack(alignment: .topLeading) {
            if phase.isVisible {
                ChipPanel(phase: phase, chips: chipsForCurrentPhase(phase))
                    .opacity(doneFading ? 0 : 1)
                    .animation(reduceMotion ? .clusterFadeReduced : .clusterFade,
                               value: doneFading)
                    .position(x: layout.anchorX, y: layout.anchorY)
                    .transition(
                        AnyTransition.opacity
                            .animation(reduceMotion ? Animation.clusterFadeReduced : Animation.haloExpand)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? .clusterFadeReduced : .haloExpand, value: phase.identity)
        .onChange(of: stateProvider.recordingState) { _, newState in
            handleRecordingStateChange(newState)
        }
        .onChange(of: stateProvider.lastPasteEvent) { _, event in
            handlePasteEvent(event)
        }
        .onAppear { handleRecordingStateChange(stateProvider.recordingState) }
    }

    // MARK: - Phase derivation
    //
    // Resolution order (highest priority first):
    //   1. donePayload window (1.2s done dwell + 0.24s fade)
    //   2. injectedFailure (W3 FailureRegistry seam)
    //   3. engine state via ClusterPhase.fromEngine

    private var derivedPhase: ClusterPhase {
        if let payload = donePayload {
            return .done(appName: payload.appName, preview: payload.preview)
        }
        if let reason = injectedFailure {
            return .failed(reason: reason)
        }
        return ClusterPhase.fromEngine(stateProvider.recordingState)
    }

    // MARK: - Chip composition

    private func chipsForCurrentPhase(_ phase: ClusterPhase) -> [ChipDescriptor] {
        ClusterChips.chips(
            phase: phase,
            recordingStartedAt: recordingStartedAt,
            audioLevel: Float(recorder.audioMeter.averagePower),
            promptIcon: stateProvider.enhancementService?.activePrompt?.icon,
            promptName: stateProvider.enhancementService?.activePrompt?.title,
            transcriptionModelLabel: stateProvider.transcriptionModelLabel,
            enhancementProviderLabel: enhancementProviderLabel,
            onRetry: handleRetry,
            onOpenSettings: handleOpenSettings
        )
    }

    private var enhancementProviderLabel: String? {
        let provider = aiService.selectedProvider.rawValue.uppercased()
        let model = aiService.currentModel
            .replacingOccurrences(of: "models/", with: "")
            .uppercased()
        guard !model.isEmpty else { return provider }
        return "\(provider) \u{00B7} \(model)"
    }

    // MARK: - Engine state handling

    private func handleRecordingStateChange(_ state: RecordingState) {
        switch state {
        case .starting, .recording:
            if recordingStartedAt == nil {
                recordingStartedAt = .now
            }
        default:
            recordingStartedAt = nil
        }

        if case .failed = state {
            scheduleFailedDwell()
        }
    }

    private func handlePasteEvent(_ event: PasteEvent?) {
        guard let event else { return }
        doneTask?.cancel()
        doneFading = false
        donePayload = DonePayload(appName: event.appName, preview: event.preview)

        doneTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .clusterFadeReduced : .clusterFade) {
                doneFading = true
            }
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            donePayload = nil
            doneFading = false
        }
    }

    private func scheduleFailedDwell() {
        failedTask?.cancel()
        let dwell = max(0.5, failedDwellSeconds)
        failedTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(dwell * 1000)))
            guard !Task.isCancelled else { return }
            injectedFailure = nil
            // Engine .failed already collapses to .idle on its own
            // (engine-side dwell). Cluster only manages the optional
            // injected failure timer.
        }
    }

    // MARK: - W3 seam

    /// W3 wires `FailureRegistry.publish(reason:)` to call this.
    /// W2 ships it unwired so the cluster is testable in isolation.
    func injectFailure(reason: String) {
        injectedFailure = reason
        scheduleFailedDwell()
    }

    // MARK: - Action chip handlers

    private func handleRetry() {
        // W2 stub. W3's FailureRegistry will define retry semantics.
        // For now, clear the injected failure so the cluster retracts —
        // the engine state machine handles real recovery via hotkey.
        injectedFailure = nil
    }

    private func handleOpenSettings() {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: ["destination": "Settings"]
        )
    }
}
