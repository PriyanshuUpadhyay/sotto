import SwiftUI

struct BayCapsule: View {
    @ObservedObject var ui: RecorderUIState
    @State private var breathePulse: Double = 0

    var body: some View {
        TacticalGlass(
            shape: BottomRoundedRectangle(bottomRadius: SottoGeometry.cornerRadiusNotch),
            phase: ui.phase,
            breathePulse: breathePulse,
            showInnerSheen: ui.phase == .enhancing
        )
        .overlay(content)
        .onPreferenceChange(BreathePulseKey.self) { breathePulse = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch ui.phase {
        case .hidden:           EmptyView()
        case .armed:            ArmingContent(ui: ui)
        case .recording, .liveText: RecordingContent(ui: ui)
        case .transcribing:     TranscribingContent(ui: ui)
        case .enhancing:        EnhancingContent(ui: ui)
        case .done:             CommittedContent(ui: ui)
        case .failed:           FailContent(ui: ui)
        }
    }
}
