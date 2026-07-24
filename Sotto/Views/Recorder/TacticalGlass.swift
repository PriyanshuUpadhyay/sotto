import SwiftUI

// MARK: - SottoGeometry
//
// Geometry tokens from spec §1.2. Constants exposed as a namespace so all
// Sotto surfaces (HUD, Settings, Main, Onboarding) consume the same values.

enum SottoGeometry {
    /// 2pt — matte app surfaces.
    static let cornerRadiusGlass: CGFloat = 2

    /// 8pt — capsule + chips (bottom-only; hard top edge).
    static let cornerRadiusNotch: CGFloat = 8

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
//   2. Give downstream recorder subviews a single import surface that survives
//      future refactors of `HaloMaterial` internals.
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
