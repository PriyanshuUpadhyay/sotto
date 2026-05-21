import SwiftUI

// MARK: - SottoGeometry
//
// Geometry tokens from spec §1.2. Constants exposed as a namespace so all
// Sotto surfaces (HUD, Settings, Main, Onboarding) consume the same values.

enum SottoGeometry {
    /// 2pt — matte app surfaces.
    static let cornerRadiusGlass: CGFloat = 2

    /// 8pt — Bay capsule + chips (bottom-only; hard top edge).
    static let cornerRadiusNotch: CGFloat = 8

    /// 6pt — Bay stalactites (slightly tighter than capsule).
    static let cornerRadiusStalactite: CGFloat = 6

    /// 0pt — brackets, dividers, tiles.
    static let cornerRadiusZero: CGFloat = 0

    /// 0.5pt — hairline border weight.
    static let hairline: CGFloat = 0.5

    /// 4pt — base spacing unit.
    static let spacingUnit: CGFloat = 4
}

// MARK: - TacticalGlass
//
// Sotto's primary material primitive. THIN WRAPPER over `HaloMaterial` — the
// 8-layer compose (NSVisualEffectView blur → onyx fill → top gloss → inner
// stroke → bottom inner stroke → state-keyed inner sheen → outer halo glow →
// drop shadow) remains the contract. Spec §3 (HaloMaterial) requires that
// `TacticalGlass` be grounded in `HaloMaterial` and NOT introduce a parallel
// material stack (e.g. a CSS-equivalent translation or a thin
// `.ultraThinMaterial` wrapper).
//
// Purpose of the wrapper:
//   1. Fix the Sotto spec defaults (onyx appearance, notch radius) so call
//      sites don't need to pass them.
//   2. Give downstream Bay subviews a single import surface that survives
//      future refactors of `HaloMaterial` internals.
//   3. Establish a typed entry point for the `BottomRoundedRectangle` shape
//      so the bay capsule + stalactites share a canonical silhouette.
//
// Reviewers compare rendered output against `HaloMaterial` previews — same
// 8 layers, same compose order.

struct TacticalGlass<S: Shape>: View {
    let shape: S
    let phase: HaloPhase
    var breathePulse: Double = 0
    var showInnerSheen: Bool = false
    var appearance: GlassAppearance = .onyx

    var body: some View {
        HaloMaterial(
            shape: shape,
            phase: phase,
            breathePulse: breathePulse,
            showInnerSheen: showInnerSheen,
            appearance: appearance
        )
    }
}

// MARK: - Convenience initializers

extension TacticalGlass where S == BottomRoundedRectangle {
    /// Bay-style bottom-rounded glass — matches notch bottom-radius, hard top edge.
    static func bay(phase: HaloPhase, radius: CGFloat = SottoGeometry.cornerRadiusNotch) -> some View {
        TacticalGlass<BottomRoundedRectangle>(
            shape: BottomRoundedRectangle(bottomRadius: radius),
            phase: phase
        )
    }
}

// MARK: - BottomRoundedRectangle
//
// Hard top edge + rounded bottom corners. Spec §1.2 `cornerRadiusNotch` is
// "8pt bottom-only" — `RoundedRectangle` rounds all four corners, so we draw
// the path manually.

struct BottomRoundedRectangle: Shape {
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(bottomRadius, min(rect.width, rect.height) / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(90),
                 clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(180),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}

#if DEBUG
#Preview("TacticalGlass — bay capsule, recording") {
    TacticalGlass.bay(phase: .recording)
        .frame(width: 220, height: 44)
        .padding(40)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("TacticalGlass — bay capsule, enhancing") {
    TacticalGlass<BottomRoundedRectangle>(
        shape: BottomRoundedRectangle(bottomRadius: SottoGeometry.cornerRadiusNotch),
        phase: .enhancing,
        breathePulse: 0.6,
        showInnerSheen: true
    )
    .frame(width: 220, height: 44)
    .padding(40)
    .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}
#endif
