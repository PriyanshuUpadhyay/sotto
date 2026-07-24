import CoreGraphics

/// The only corner radii Sotto uses. Replaces the ad-hoc spread of ~14 literal
/// values (2,3,4,5,6,7,9,10,12,13,14,16,18,22,30) audited 2026-06-03.
/// Nested surfaces derive their radius via `inner(of:inset:)` so corners stay
/// concentric (Liquid Glass concentricity): inner = outer − inset.
enum Radius {
    /// 6 — small controls, chips, icon tiles, key caps.
    static let control: CGFloat = 6
    /// 10 — rows, list cards, inline cards.
    static let card: CGFloat = 10
    /// 16 — panels, large cards, sheets, command palette.
    static let panel: CGFloat = 16
    /// 22 — the recorder HUD pill / notch capsule.
    static let hud: CGFloat = 22
    /// 19 — the compact matte recorder capsule (half of ~38pt capsule height).
    static let capsule: CGFloat = 19

    /// Concentric inner radius for a surface inset by `inset` from its parent.
    static func inner(of outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, outer - inset)
    }
}
