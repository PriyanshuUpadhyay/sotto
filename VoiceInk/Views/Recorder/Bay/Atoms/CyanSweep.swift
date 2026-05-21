import SwiftUI

struct CyanSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var t: Double = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(
                colors: [.clear, Palette.transCyan.opacity(0.6), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: w * 0.35)
            .offset(x: reduceMotion ? 0 : (-w * 0.35 + (w + w * 0.35) * t))
            .opacity(reduceMotion ? 0.4 : 1)
            .onAppear { if !reduceMotion { t = 1 } }
            .animation(reduceMotion ? nil : MotionTokens.sweep.repeatForever(autoreverses: false),
                       value: t)
        }
        .allowsHitTesting(false)
    }
}
