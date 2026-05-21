import SwiftUI

struct EnhancingContent: View {
    @ObservedObject var ui: RecorderUIState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: Double = 0.25

    var body: some View {
        HStack(spacing: 10) {
            AudioBars(level: 0.3, frozen: true, tint: Palette.enhViolet)
            MonoLabel(text: "ENHANCING…", size: 10.5, color: Palette.enhViolet)
        }
        .preference(key: BreathePulseKey.self, value: reduceMotion ? 0.5 : breath)
        .onAppear { if !reduceMotion { breath = 0.6 } }
        .animation(reduceMotion ? nil : MotionTokens.breathe.repeatForever(autoreverses: true),
                   value: breath)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Enhancing")
    }
}

struct BreathePulseKey: PreferenceKey {
    static var defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
}
