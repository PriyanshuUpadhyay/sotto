import SwiftUI
import AppKit

/// Appearance-adaptive semantic tokens for Sotto's WINDOWED surfaces
/// (Main / Settings / History / Onboarding / Command palette). These resolve
/// from macOS system colors + materials so every window respects light/dark,
/// Increase Contrast, and Reduce Transparency for free.
///
/// The onyx `Palette` ladder is now scoped to the Recorder HUD ONLY — do not
/// use `Palette.surface*` / `Palette.textPrimary` on windowed surfaces.
enum Theme {
    // MARK: Surfaces (colors)
    /// Window background. Adapts light/dark.
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    /// Grouped/content background behind cards.
    static let groupedBackground = Color(nsColor: .controlBackgroundColor)
    /// Elevated card/control fill.
    static let elevated = Color(nsColor: .underPageBackgroundColor)
    /// Separator / hairline.
    static let separator = Color(nsColor: .separatorColor)

    // MARK: Ink (text) — aliases over SwiftUI semantics for discoverability.
    static let inkPrimary = Color.primary
    static let inkSecondary = Color.secondary
    static let inkTertiary = Color.secondary.opacity(0.6)

    // MARK: Materials — preferred Liquid-Glass substrate per surface.
    enum Material {
        /// Sidebars, toolbars — the most translucent.
        static let chrome: SwiftUI.Material = .bar
        /// Panels / cards on a window.
        static let panel: SwiftUI.Material = .regularMaterial
        /// Lightweight nested fills.
        static let nested: SwiftUI.Material = .thinMaterial
    }
}

extension Theme {
    // Appearance-adaptive matte aliases. Content surfaces stay flat graphite;
    // shell and rail surfaces can still use `Material.chrome`.
    static let canvas = Palette.mtCanvas
    static let panel = Palette.mtRaise
    static let selectedRow = Palette.mtRaise2
    static let hairline = Palette.mtLine
    static let hairlineStrong = Palette.mtLine2
}
