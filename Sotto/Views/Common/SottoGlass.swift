import SwiftUI

// MARK: - SottoGlass
//
// ONE material for the floating recorder family — the recording capsule, the
// post-paste ping, the review editor, the command palette and the dictionary
// quick-add panel. It is the PLATFORM material (macOS 26 `.glassEffect`),
// tinted for Sotto's identity; it is never a hand-rolled blur stack.
//
// The levels differ only in how thick the glass reads (mockup 01 lane B: the
// review box is "the same glass, one step thicker"). `.chip` and `.band` are
// deliberately NOT live glass: both carry `Palette.ink*` text, and text must
// never sit on bare glass whose composite depends on the wallpaper behind the
// window. They are a semi-opaque frost from the same `mt*` ladder, so the
// composite over ANY backdrop is computable — which is what keeps
// `MatteContrastTests` a real assertion instead of a guess.
//
// Accessibility branches once, at the top of `body`:
//   • Reduce Transparency → the pre-glass opaque matte body (kept alive).
//   • Increase Contrast   → solid fill + `A11y.borderColor(increaseContrast:)`.
//   • Reduce Motion       → `.glassEffectTransition(.identity)`; no morph.

enum SottoGlassLevel {
    /// The recording capsule and the post-paste ping — the thinnest glass.
    case capsule
    /// The review editor / palette / quick-add card — one step thicker.
    case panel
    /// A chip riding ON another surface (esc hint, retry, key hint, version
    /// segment). Frosted, not glass: it carries small ink.
    case chip
    /// The legibility band directly behind transcript text. Frosted, not glass.
    case band
}

extension SottoGlassLevel {
    fileprivate var isFrost: Bool {
        switch self {
        case .chip, .band: return true
        case .capsule, .panel: return false
        }
    }

    /// Live-glass body tint. Unused by the frost levels.
    fileprivate var tint: Color {
        switch self {
        case .panel: return Palette.glassTintThick
        default:     return Palette.glassTint
        }
    }

    /// Semi-opaque frost fill. Unused by the glass levels.
    fileprivate var frostFill: Color {
        switch self {
        case .chip: return Palette.glassChipFill
        default:    return Palette.glassBand
        }
    }

    /// Opaque fallback under Reduce Transparency / Increase Contrast — today's
    /// matte ladder, unchanged.
    fileprivate var opaqueFill: Color {
        switch self {
        case .chip, .band: return Palette.mtRaise2
        case .capsule, .panel: return Palette.mtRaise
        }
    }

    /// Accent-glow blur radius and alpha — the state colour does not sit on the
    /// surface, it bleeds through as a glow (mockup 01 lane B `.b-cap`).
    fileprivate var glowRadius: CGFloat {
        switch self {
        case .panel: return 23
        default:     return 15
        }
    }

    fileprivate var glowAlpha: Double {
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
    /// Pressable surfaces get interactive glass so a press deforms the material.
    let interactive: Bool
    /// Morph identity — adjacent glass in the same `GlassEffectContainer` blends
    /// and a phase change morphs instead of swapping.
    let glassID: String?
    let namespace: Namespace.ID?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background(backdrop)
    }

    @ViewBuilder
    private var backdrop: some View {
        if reduceTransparency || contrast == .increased {
            opaqueBody
        } else if level.isFrost {
            frostBody
        } else {
            glassBody
        }
    }

    // MARK: Substrates

    private var glassBody: some View {
        let substrate = Color.clear.glassEffect(glass, in: shape)
        return Group {
            // A morph identity only exists where the caller has a phase change
            // to express; without one the surface stays out of every union.
            if let glassID, let namespace {
                substrate.glassEffectID(glassID, in: namespace)
            } else {
                substrate
            }
        }
        .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        .overlay(edgeHighlight)
        .overlay(innerShadow)
    }

    /// A frosted region: the same `mt*` ladder at `Palette.glassFrostAlpha`, so
    /// ink over it clears AA against ANY wallpaper (`MatteContrastTests`).
    private var frostBody: some View {
        shape.fill(level.frostFill)
            .overlay(shape.strokeBorder(Palette.hairlineSoft, lineWidth: 1))
            .overlay(edgeHighlight)
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

    // MARK: Layers

    /// The bright top edge — light entering the material.
    private var edgeHighlight: some View {
        shape.strokeBorder(
            LinearGradient(colors: [Palette.glassEdgeHi, .clear],
                           startPoint: .top, endPoint: .center),
            lineWidth: 1
        )
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// The material's own thickness, read as a soft darkening along the bottom.
    private var innerShadow: some View {
        shape.fill(
            LinearGradient(colors: [.clear, Palette.glassInnerShadow],
                           startPoint: .center, endPoint: .bottom)
        )
        .allowsHitTesting(false)
    }

    private var glass: Glass {
        let base = Glass.regular.tint(level.tint)
        return interactive ? base.interactive() : base
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

// MARK: - Ink on bare glass
//
// Short ink that rides the glass itself rather than a band (the capsule's timer,
// the ping's caption, the review header) gets the mockup's own answer: a soft
// shadow that separates the glyphs from whatever the desktop puts behind them.
// Transcript text never relies on this — it gets a band.

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
    /// Separates short ink from the desktop behind the glass. Use a frosted
    /// band instead wherever the user reads a transcript.
    func glassInkShadow() -> some View { modifier(GlassInkShadow()) }

    /// Paints the shared Sotto glass behind this view. See `SottoGlassLevel`
    /// for what each level is made of.
    func sottoGlass<S: InsettableShape>(
        _ level: SottoGlassLevel,
        in shape: S,
        interactive: Bool = false,
        id: String? = nil,
        namespace: Namespace.ID? = nil
    ) -> some View {
        modifier(SottoGlassBackground(level: level, shape: shape,
                                      interactive: interactive,
                                      glassID: id, namespace: namespace))
    }

    /// Bleeds the state colour through the glass as a glow. Apply OUTSIDE any
    /// clip or mask the surface uses.
    func sottoGlassGlow(_ color: Color?, level: SottoGlassLevel) -> some View {
        modifier(SottoGlassGlow(color: color, level: level))
    }
}
