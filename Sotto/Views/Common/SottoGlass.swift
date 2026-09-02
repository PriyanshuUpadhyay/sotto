import SwiftUI

// MARK: - SottoGlass
//
// ONE material for the floating recorder family — the recording capsule, the
// post-paste ping, the review editor, the command palette and the dictionary
// quick-add panel. It is the PLATFORM material (macOS 26 `.glassEffect`); it is
// never a hand-rolled blur stack, and it never gets a hand-drawn rim: Liquid
// Glass lenses the backdrop and lights its own silhouette, so an added stroke
// only reads as a hard edge the material does not have.
//
// `Glass.regular` is used everywhere. Apple's rule: regular blurs AND adjusts
// the luminosity of the background so foreground text stays legible, and is the
// variant for components carrying a significant amount of text; `Glass.clear`
// is only for elements floating over media and needs its own dimming layer.
// Every Sotto surface here carries text, so regular owns the legibility and no
// frost is painted behind it.
//
// The glass is left UNTINTED by default — Liquid Glass has no inherent colour
// and takes its colour from what is behind it, which is what makes it read as
// glass rather than as a dark slab. A tint is passed only where colour is a
// status signal (the capsule's terminal states).
//
// `.chip` and `.scrim` are NOT glass. Apple forbids glass on glass: elements
// sitting on a glass surface use fills, transparency and vibrancy so they read
// as a thin overlay that is part of the material. So a chip is a light lift and
// a scrim is a soft recess — both low-alpha fills, both borderless.
//
// Accessibility branches once, at the top of `body`:
//   • Reduce Transparency → the pre-glass opaque matte body (kept alive).
//   • Increase Contrast   → solid fill + `A11y.borderColor(increaseContrast:)`.

enum SottoGlassLevel {
    /// The recording capsule and the post-paste ping — the thinnest glass.
    case capsule
    /// The review editor / palette / quick-add card — one step thicker.
    case panel
    /// A control riding ON a glass surface (esc hint, retry, key cap, version
    /// segment). A light lift, not a second sheet of glass.
    case chip
    /// A soft recess behind a long stretch of transcript text. Not glass.
    case scrim
}

extension SottoGlassLevel {
    /// True for the levels that are a fill on top of glass rather than glass.
    var isOverlay: Bool {
        switch self {
        case .chip, .scrim: return true
        case .capsule, .panel: return false
        }
    }

    /// Fill for the overlay levels. Unused by the glass levels.
    var overlayFill: Color {
        switch self {
        case .chip: return Palette.glassChipFill
        default:    return Palette.glassScrim
        }
    }

    /// Opaque fallback under Reduce Transparency / Increase Contrast — today's
    /// matte ladder, unchanged.
    var opaqueFill: Color {
        switch self {
        case .chip, .scrim: return Palette.mtRaise2
        case .capsule, .panel: return Palette.mtRaise
        }
    }

    /// Accent-glow blur radius and alpha — the state colour does not sit on the
    /// surface, it bleeds through as a glow (mockup 01 lane B `.b-cap`).
    var glowRadius: CGFloat {
        switch self {
        case .panel: return 23
        default:     return 15
        }
    }

    var glowAlpha: Double {
        switch self {
        case .panel: return 0.15
        default:     return 0.20
        }
    }
}

// MARK: - SottoGlassBackground

struct SottoGlassBackground<S: InsettableShape>: ViewModifier {
    let level: SottoGlassLevel
    let shape: S
    /// Stained-glass tint. Apple reserves colour on glass for elements that
    /// truly benefit from emphasis — status indicators and primary actions —
    /// so this stays nil on everything except a terminal capsule state.
    let tint: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(opaqueBody)
        } else if level.isOverlay {
            content.background(shape.fill(level.overlayFill))
        } else {
            // The content is the glass view's OWN content, never a sibling
            // layer over a `Color.clear` lens: `glassEffect` captures what it
            // is attached to, and a `.background` lens blurred the capsule's
            // own words on device.
            content.glassEffect(glass, in: shape)
        }
    }

    private var opaqueBody: some View {
        shape.fill(level.opaqueFill)
            .overlay(
                shape.strokeBorder(
                    A11y.borderColor(increaseContrast: contrast == .increased),
                    lineWidth: 1
                )
            )
    }

    private var glass: Glass {
        guard let tint else { return .regular }
        return Glass.regular.tint(tint)
    }
}

// MARK: - Accent glow
//
// Separate from the material because it must be painted OUTSIDE the caller's
// clip: the capsule and the ping both mask themselves to the revealed span, and
// a glow drawn inside that mask would be cropped to nothing.

struct SottoGlassGlow: ViewModifier {
    let color: Color?
    let level: SottoGlassLevel

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        // Increase Contrast suppresses decorative glows app-wide
        // (`AdaptiveGlass.contrastedHaloDisabled`); the solid border carries the
        // state instead.
        let suppressed = contrast == .increased && AdaptiveGlass.contrastedHaloDisabled
        return content.shadow(
            color: (suppressed ? nil : color)?.opacity(level.glowAlpha) ?? .clear,
            radius: level.glowRadius
        )
    }
}

// MARK: - Ink on glass
//
// Regular glass adjusts the luminosity behind it to keep foreground text
// legible, so ink sits on the material directly. This adds the last bit of
// separation for small ink over a busy desktop.

struct GlassInkShadow: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        // The surface is opaque in both of these, so the shadow would only
        // smudge the glyphs.
        if reduceTransparency || contrast == .increased {
            content
        } else {
            content.shadow(color: Palette.glassInkShadow, radius: 2, x: 0, y: 1)
        }
    }
}

extension View {
    /// Separates ink from the desktop behind the glass.
    func glassInkShadow() -> some View { modifier(GlassInkShadow()) }

    /// Paints the shared Sotto glass behind this view. See `SottoGlassLevel`
    /// for what each level is made of.
    func sottoGlass<S: InsettableShape>(
        _ level: SottoGlassLevel,
        in shape: S,
        tint: Color? = nil
    ) -> some View {
        modifier(SottoGlassBackground(level: level, shape: shape, tint: tint))
    }

    /// Bleeds the state colour through the glass as a glow. Apply OUTSIDE any
    /// clip or mask the surface uses.
    func sottoGlassGlow(_ color: Color?, level: SottoGlassLevel) -> some View {
        modifier(SottoGlassGlow(color: color, level: level))
    }
}
