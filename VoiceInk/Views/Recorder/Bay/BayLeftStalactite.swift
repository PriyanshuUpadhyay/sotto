import SwiftUI

struct BayLeftStalactite: View {
    @ObservedObject var ui: RecorderUIState

    var body: some View {
        if shouldShow {
            TacticalGlass(
                shape: BottomRoundedRectangle(bottomRadius: SottoGeometry.cornerRadiusStalactite),
                phase: ui.phase
            )
            .overlay(
                Text(ui.activePromptLabel ?? "")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .tracking(0.16 * 10.5)
                    .foregroundStyle(Palette.brandAcid)
                    .accessibilityLabel("Prompt \(ui.activePromptLabel ?? "")")
            )
            .transition(.opacity.animation(MotionTokens.stateEnter))
        }
    }

    private var shouldShow: Bool {
        guard let label = ui.activePromptLabel, !label.isEmpty else { return false }
        switch ui.phase {
        case .recording, .liveText: return true
        default: return false
        }
    }
}
