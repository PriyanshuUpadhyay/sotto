import SwiftUI

struct AudioBars: View {
    let level: Double
    let frozen: Bool
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(tint.opacity(barOpacity))
                    .frame(width: 2.5, height: heightFor(index: i))
            }
        }
        .onAppear { if !reduceMotion && !frozen { phase = 1 } }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                   value: phase)
        .accessibilityHidden(true)
    }

    private var barOpacity: Double {
        guard frozen else { return 1 }
        return contrast == .increased ? 1 : 0.35
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
