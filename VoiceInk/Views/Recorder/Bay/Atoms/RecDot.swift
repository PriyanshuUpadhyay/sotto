import SwiftUI

struct RecDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false

    var body: some View {
        Circle()
            .fill(Palette.recRed)
            .frame(width: 8, height: 8)
            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.15 : 0.9))
            .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.7))
            .animation(reduceMotion ? nil : MotionTokens.pulse.repeatForever(autoreverses: true),
                       value: pulse)
            .onAppear { if !reduceMotion { pulse = true } }
            .accessibilityHidden(true)
    }
}
