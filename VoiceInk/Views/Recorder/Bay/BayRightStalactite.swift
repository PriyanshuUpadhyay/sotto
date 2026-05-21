import SwiftUI

struct BayRightStalactite: View {
    @ObservedObject var ui: RecorderUIState

    var body: some View {
        if let action = currentAction {
            Button(action: action.handler) {
                TacticalGlass(
                    shape: BottomRoundedRectangle(bottomRadius: SottoGeometry.cornerRadiusStalactite),
                    phase: ui.phase
                )
                .overlay(
                    Text("\u{25B8} \(action.label)")    // U+25B8 ▸ tappable glyph
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .tracking(0.16 * 10.5)
                        .foregroundStyle(Palette.brandAcid)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.label)
            .transition(.opacity.animation(MotionTokens.stateEnter))
        }
    }

    private struct Action {
        let label: String
        let handler: () -> Void
    }

    private var currentAction: Action? {
        switch ui.phase {
        case .recording, .liveText:
            return Action(label: "SAVE") {
                NotificationCenter.default.post(name: .voiceInkSaveRecording, object: nil)
            }
        case .done:
            return Action(label: "UNDO") {
                NotificationCenter.default.post(name: .voiceInkUndoLastPaste, object: nil)
            }
        default:
            return nil
        }
    }
}

extension Notification.Name {
    static let voiceInkSaveRecording = Notification.Name("voiceInkSaveRecording")
    static let voiceInkUndoLastPaste = Notification.Name("voiceInkUndoLastPaste")
}
