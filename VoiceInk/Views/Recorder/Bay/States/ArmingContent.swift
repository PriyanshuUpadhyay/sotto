import SwiftUI

struct ArmingContent: View {
    @ObservedObject var ui: RecorderUIState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: Double = 0.4

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Palette.brandAcid.opacity(reduceMotion ? 0.7 : breath))
                .frame(width: 6, height: 6)

            MonoLabel(text: "LISTENING", size: 10.5)
        }
        .onAppear {
            guard !reduceMotion else { return }
            breath = 0.9
        }
        .animation(reduceMotion ? nil : MotionTokens.arming.repeatForever(autoreverses: true),
                   value: breath)
        .accessibilityLabel("Listening")
        .accessibilityAddTraits(.isHeader)
    }
}
