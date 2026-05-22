import SwiftUI

struct FailContent: View {
    @ObservedObject var ui: RecorderUIState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var uiManager: RecorderUIManager
    @State private var blink: Bool = false

    var body: some View {
        Button(action: { uiManager.dismissFailedPhase() }) {
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.recRed)
                    .opacity(reduceMotion ? 1 : (blink ? 1 : 0.4))

                MonoLabel(
                    text: ui.errorCode ?? "ERR · UNKNOWN",
                    size: 10.5,
                    color: Palette.recRed
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { if !reduceMotion { blink = true } }
        .animation(reduceMotion ? nil : MotionTokens.blink.repeatForever(autoreverses: true),
                   value: blink)
        .accessibilityLabel("Failed, \(ui.errorCode ?? "unknown"). Tap to dismiss.")
    }
}
