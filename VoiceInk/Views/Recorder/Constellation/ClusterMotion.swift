import SwiftUI

// MARK: - Sanctioned animations
//
// Spec §1 + §4. Reduce-Motion: callers branch on
// `@Environment(\.accessibilityReduceMotion)` and substitute `clusterFadeReduced`
// (0.18s opacity) — these animations are NEVER applied under Reduce-Motion.

extension Animation {
    /// 1.0s ring pulse — recording / failed dot. Half-period 0.5s.
    static let ringPulse = Animation
        .easeInOut(duration: 0.5)
        .repeatForever(autoreverses: true)

    /// 1.6s ring pulse — enhancing dot. Half-period 0.8s.
    static let ringPulseSlow = Animation
        .easeInOut(duration: 0.8)
        .repeatForever(autoreverses: true)

    /// 1.4s chip α 0.62 ↔ 1.0 shimmer — transcribing chip. Half-period 0.7s.
    static let chipShimmer = Animation
        .easeInOut(duration: 0.7)
        .repeatForever(autoreverses: true)

    /// 1.6s chip breath halo — enhancing chip. Half-period 0.8s.
    static let chipBreath = Animation
        .easeInOut(duration: 0.8)
        .repeatForever(autoreverses: true)

    /// 0.24s linear cluster collapse + per-chip cross-fade. Spec §1.
    static let clusterFade = Animation.linear(duration: 0.24)

    /// 0.18s linear opacity — Reduce-Motion fallback for both directions
    /// (entry, exit, cross-fades). Spec §1.
    static let clusterFadeReduced = Animation.linear(duration: 0.18)
}

// MARK: - RingPulseDot
//
// Leading dot + animated outer ring. The ring scales 0.6 → 1.0 and fades
// 0.55 → 0 across the half-period; the dot itself stays static at full alpha.
// Two cadences: `.fast` (recording/failed, 0.5s half-period) and `.slow`
// (enhancing, 0.8s half-period). `.none` renders a static disc with no ring.

enum RingPulseRate {
    case fast
    case slow
    case none
}

struct RingPulseDot: View {
    let color: Color
    var rate: RingPulseRate = .fast
    var diameter: CGFloat = 6
    var ringDiameter: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.accentGlow, lineWidth: 1)
                .frame(width: ringDiameter, height: ringDiameter)
                .scaleEffect(pulse ? 1.0 : 0.6)
                .opacity(ringOpacity)
                .opacity(rate == .none ? 0 : 1)

            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .onAppear { applyAnimation() }
        .onChange(of: rate) { _, _ in applyAnimation() }
        .onChange(of: reduceMotion) { _, _ in applyAnimation() }
        .accessibilityHidden(true)
    }

    private var ringOpacity: Double {
        guard rate != .none else { return 0 }
        return pulse ? 0.0 : 0.55
    }

    private func applyAnimation() {
        guard !reduceMotion else {
            pulse = false
            return
        }
        let anim: Animation? = {
            switch rate {
            case .fast: return .ringPulse
            case .slow: return .ringPulseSlow
            case .none: return nil
            }
        }()
        withAnimation(anim) { pulse.toggle() }
    }
}

// MARK: - ChipShimmer
//
// Transcribing chip α cycle 0.62 ↔ 1.0 over 1.4s. Reduce-Motion → static at 1.0.

struct ChipShimmer: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(active && dim ? 0.62 : 1.0)
            .onAppear { applyAnimation() }
            .onChange(of: active) { _, _ in applyAnimation() }
            .onChange(of: reduceMotion) { _, _ in applyAnimation() }
    }

    private func applyAnimation() {
        if reduceMotion || !active {
            dim = false
            return
        }
        withAnimation(.chipShimmer) { dim.toggle() }
    }
}

// MARK: - ChipBreath
//
// Enhancing chip outer halo cycle. Renders an extra accent shadow whose
// radius+alpha cycles. Reduce-Motion → static mid-amplitude (no animation).

struct ChipBreath: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var raised: Bool = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: Palette.accent.opacity(haloAlpha),
                radius: haloRadius,
                x: 0,
                y: 0
            )
            .onAppear { applyAnimation() }
            .onChange(of: active) { _, _ in applyAnimation() }
            .onChange(of: reduceMotion) { _, _ in applyAnimation() }
    }

    private var haloAlpha: Double {
        guard active else { return 0 }
        if reduceMotion { return 0.32 }
        return raised ? 0.45 : 0.20
    }

    private var haloRadius: CGFloat {
        guard active else { return 0 }
        if reduceMotion { return 10 }
        return raised ? 14 : 8
    }

    private func applyAnimation() {
        if reduceMotion || !active {
            raised = false
            return
        }
        withAnimation(.chipBreath) { raised.toggle() }
    }
}

extension View {
    func chipShimmer(active: Bool) -> some View {
        modifier(ChipShimmer(active: active))
    }

    func chipBreath(active: Bool) -> some View {
        modifier(ChipBreath(active: active))
    }
}
