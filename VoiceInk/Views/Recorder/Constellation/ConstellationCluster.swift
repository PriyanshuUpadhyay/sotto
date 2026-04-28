import SwiftUI
import AppKit

// MARK: - ConstellationCluster
//
// Orchestrator for the chip cluster. Owns:
//   • RecordingState → ClusterPhase derivation
//   • Done-dwell synthesis (1.2s + 0.24s fade) keyed off PasteEvent
//   • Failed-dwell timer (read AppStorage("failedDwellSeconds"), default 6s)
//   • FailureRegistry subscription
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
    @EnvironmentObject var failureRegistry: FailureRegistry
    let mode: HaloShape.Mode

    /// Failure dwell. 3.0 / 6.0 = auto-acknowledge after seconds;
    /// `.infinity` = persist until RETRY / OPEN SETTINGS / external ack.
    @AppStorage("failedDwellSeconds") private var failedDwellSeconds: Double = 6.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Phase state

    @State private var activeFailure: FailureEvent? = nil
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
        .onReceive(failureRegistry.$current) { event in
            handleFailureEvent(event)
        }
        .onAppear { handleRecordingStateChange(stateProvider.recordingState) }
    }

    // MARK: - Phase derivation
    //
    // Resolution order (highest priority first):
    //   1. donePayload window (1.2s done dwell + 0.24s fade)
    //   2. activeFailure (sourced from FailureRegistry)
    //   3. engine state via ClusterPhase.fromEngine

    private var derivedPhase: ClusterPhase {
        if let payload = donePayload {
            return .done(appName: payload.appName, preview: payload.preview)
        }
        if let event = activeFailure {
            return .failed(reason: event.reason)
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

    private func handleFailureEvent(_ event: FailureEvent?) {
        failedTask?.cancel()
        activeFailure = event
        guard let event else { return }
        scheduleFailedDwell(for: event.id)
    }

    /// Auto-ack timer for the cluster's `.failed` dwell. Three modes:
    ///   • finite dwell (3.0 / 6.0) → sleep then `failureRegistry.acknowledge`
    ///   • `.infinity` sentinel → no auto-ack; wait for retry success or
    ///     OPEN SETTINGS (which clears the registry via the notification
    ///     observer wired in `FailureRegistry.installSettingsAckObserver`).
    private func scheduleFailedDwell(for id: UUID) {
        let dwell = failedDwellSeconds
        guard dwell.isFinite else { return }
        let bounded = max(0.5, dwell)
        failedTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(bounded * 1000)))
            guard !Task.isCancelled else { return }
            failureRegistry.acknowledge(id)
        }
    }

    // MARK: - Action chip handlers

    private func handleRetry() {
        // RETRY chip is informational + visual. Per spec: ack ONLY on retry
        // success — so the dot stays if the retry also fails. The user
        // re-records via the existing toggle hotkey path; the registry
        // clears on the next clean run via `clearAll` from `runPipeline`.
    }

    private func handleOpenSettings() {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: ["destination": "Settings"]
        )
    }
}
