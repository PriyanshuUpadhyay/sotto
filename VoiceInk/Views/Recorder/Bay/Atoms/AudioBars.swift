import SwiftUI

struct AudioBars: View {
    let level: Double
    let frozen: Bool
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(tint.opacity(frozen ? 0.35 : 1))
                    .frame(width: 2.5, height: heightFor(index: i))
            }
        }
        .onAppear { if !reduceMotion && !frozen { phase = 1 } }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                   value: phase)
        .accessibilityHidden(true)
    }

    private func heightFor(index i: Int) -> CGFloat {
        let stagger = Double(i) * 0.18
        let base = reduceMotion ? 0.5 : 0.4 + 0.6 * (0.5 + 0.5 * sin(phase * .pi + stagger))
        let scaled = base * level.clamped(to: 0.2...1.0)
        return CGFloat(6 + scaled * 12)
    }
}

private extension Double {
    func clamped(to r: ClosedRange<Double>) -> Double { min(max(self, r.lowerBound), r.upperBound) }
}
