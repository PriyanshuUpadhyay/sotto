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

    /// A whisper of state colour, not a bath: at 0.20 the glass sampled the
    /// halo and the whole recording pill read red (owner feedback on device).
    var glowAlpha: Double {
        switch self {
        case .panel: return 0.15
        default:     return 0.10
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

// MARK: - Depth (drop shadow + accent glow)
//
// Painted as blurred SHAPES behind the surface, never with `.shadow()`: a
// shadow takes its silhouette from the rendered alpha, and a Liquid Glass lens
// renders a rectangular alpha, so `.shadow()` (and the window's own shadow)
// painted a faint square behind every rounded surface on device. The shapes
// live OUTSIDE the caller's clip or mask, which would otherwise crop them.

struct SottoGlassDepth<S: Shape>: ViewModifier {
    let shape: S
    let glow: Color?
    let level: SottoGlassLevel
    /// Explicit shadow colour (already carrying its alpha); nil = black at the level's alpha.
    let shadowColor: Color?

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        // Increase Contrast suppresses decorative glows app-wide
        // (`AdaptiveGlass.contrastedHaloDisabled`); the solid border carries the
        // state instead.
        let suppressed = contrast == .increased && AdaptiveGlass.contrastedHaloDisabled
        return content.background(
            ZStack {
                shape.fill(shadowColor ?? Color.black.opacity(level.shadowAlpha))
                    .blur(radius: level.shadowRadius)
                    .offset(y: level.shadowOffsetY)
                if let glow, !suppressed {
                    shape.fill(glow.opacity(level.glowAlpha))
                        .blur(radius: level.glowRadius)
                }
            }
            .allowsHitTesting(false)
        )
    }
}

extension SottoGlassLevel {
    var shadowAlpha: Double {
        switch self {
        case .panel: return 0.35
        default:     return 0.40
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .panel: return 24
        default:     return 15
        }
    }

    var shadowOffsetY: CGFloat { 12 }
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

    /// Paints the surface's depth — drop shadow plus the optional state glow —
    /// as blurred copies of `shape` behind this view. Apply OUTSIDE any clip or
    /// mask the surface uses, with the shape of the VISIBLE surface.
    func sottoGlassDepth<S: Shape>(
        in shape: S,
        glow: Color? = nil,
        level: SottoGlassLevel,
        shadowColor: Color? = nil
    ) -> some View {
        modifier(SottoGlassDepth(shape: shape, glow: glow, level: level, shadowColor: shadowColor))
    }
}

// MARK: - Lens shape
//
// `glassEffect(in:)` given a `RoundedRectangle` is mapped onto a rectangular
// effect view with a corner radius, and on device that view painted a faint
// rectangular tint into the corner pockets outside the radius. A custom shape
// with the same path is masked as a path instead, which is what the capsule's
// `TrailingInsetCapsule` already gets. Use this for every rounded lens.
struct SottoLensRect: InsettableShape {
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect.insetBy(dx: insetAmount, dy: insetAmount),
             cornerRadius: max(cornerRadius - insetAmount, 0), style: .continuous)
    }

    func inset(by amount: CGFloat) -> SottoLensRect {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
