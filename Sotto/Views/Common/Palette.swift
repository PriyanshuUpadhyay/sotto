import AppKit
import SwiftUI

/// Functional accents for Sotto UI. Single source of truth for brand + state
/// colors. Source of truth:
/// - Brand accent: `docs/superpowers/specs/2026-05-11-sotto-ui-redesign-design.md` §1.4
/// - State tokens: spec §4.2 (recRed / commitGreen / transCyan / enhViolet)
///
/// Usage:
/// - `Palette.brandAcid` for the Sotto brand mark, wordmark stop, selected row,
///   section labels, prompt glyph, CTA halo, HUD audio bars (Acid Lime).
/// - `Palette.recRed` for the recording dot + fail state.
/// - `Palette.commitGreen` for committed (post-paste) halo.
/// - `Palette.transCyan` for transcribing sweep + capsule border.
/// - `Palette.enhViolet` for enhancing halo breath.
/// - `Palette.success` only for true completion / validation success.
/// - `Palette.hairline` / `hairlineSoft` for glass borders.
/// - `Palette.innerHi` for the top-edge sheen on glass surfaces.
enum Palette {
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255,
                alpha: 1
            )
        }))
    }

    /// Adaptive colour whose ALPHA also differs by appearance — an overlay that
    /// should read as the same lift needs a different alpha over a light and a
    /// dark surface.
    static func adaptive(light: UInt32, lightAlpha: Double,
                         dark: UInt32, darkAlpha: Double) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        }))
    }

    /// Completion signal. Dark keeps #30D158; Light uses a contrast-safe green.
    static let success = adaptive(light: 0x2f6f1d, dark: 0x30d158)

    /// Warning signal. Dark keeps #FF9F0A; Light uses a contrast-safe amber.
    static let warn = adaptive(light: 0x8a4b00, dark: 0xff9f0a)

    /// Idle baseline. Dark keeps #8E8E93; Light uses a stronger system gray.
    static let neutral = adaptive(light: 0x515157, dark: 0x8e8e93)

    /// #0F0F12-ish — onyx backdrop tone for the cinematic walkthrough host
    /// and other dark-mode surfaces that anchor a `.onyx` GlassCard. Matches
    /// the previously-hardcoded `Color(red: 0.06, green: 0.06, blue: 0.07)`.
    /// Kept transitionally; AppDelegate host migrates to `onyxBg` in W4.
    static let onyxBackground = Color(red: 0.06, green: 0.06, blue: 0.07)

    /// Dark #D4FF3A — Acid Lime brand accent. Wordmark stop,
    /// selected row, section labels, prompt glyph, CTA halo, HUD audio bars.
    /// Source of truth: spec §1.4. Single source of truth — no inline hex
    /// permitted at call sites; consume via `Palette.brandAcid`.
    static let brandAcid = adaptive(light: 0x3d6b00, dark: 0xd4ff3a)

    /// `brandAcid` α 0.42 — muted lime fill (chip backgrounds, halo bases).
    static let brandAcidMuted = brandAcid.opacity(0.42)

    /// `brandAcid` α 0.55 — lime glow (halo end frames, shadow tints).
    static let brandAcidGlow = brandAcid.opacity(0.55)

    /// Recording dot and fail state (Dark #FF3B30; spec §4.2).
    static let recRed = adaptive(light: 0xb42318, dark: 0xff3b30)

    /// Committed halo. Named alias for spec §4.2 parity;
    /// shares the value with `success`.
    static let commitGreen = success

    /// Transcribing sweep and capsule border (Dark #5AC8FA; spec §4.2).
    static let transCyan = adaptive(light: 0x006b8f, dark: 0x5ac8fa)

    /// Enhancing halo breath and arc spin (Dark #BF5AF2; spec §4.2).
    static let enhViolet = adaptive(light: 0x6941a5, dark: 0xbf5af2)

    /// #0A0A0D — onyx background. Replaces the previously-hardcoded
    /// `Color(red: 0.06, green: 0.06, blue: 0.07)` in onyx hosts.
    static let onyxBg = Color(red: 0.039, green: 0.039, blue: 0.051)

    /// #EDEDF0 — onyx foreground (primary text on onyx surfaces).
    static let onyxFg = Color(red: 0.929, green: 0.929, blue: 0.941)

    /// #8A8A93 — onyx muted (secondary text). Same hue as `neutral` but
    /// pinned in case `neutral` shifts under a future system-color rebase.
    static let onyxMute = Color(red: 0.541, green: 0.541, blue: 0.576)

    /// White α 0.16 — hairline border on glass surfaces (locked).
    static let hairline = Color.white.opacity(0.16)

    /// White α 0.10 — softer hairline for nested or secondary edges.
    static let hairlineSoft = Color.white.opacity(0.10)

    /// White α 0.22 — inner highlight on glass surfaces (the bright-edge sheen
    /// at the top of a glass chip / panel).
    static let innerHi = Color.white.opacity(0.22)

    // MARK: - Onyx surface ladder (main-window structural tokens)
    //
    // NOTE: onyx ladder is HUD-scoped. Windowed surfaces use Theme.*, not these.
    //
    // Depth comes from a stepped surface ladder + hairlines (Raycast model),
    // not stacked translucency. Each step ~one shade lighter = one layer closer.
    // Window background → header band → cards → controls. Never skip a level
    // (base→overlay with nothing between reads as a hole). Text is
    // white-with-alpha so it composites cleanly over any surface or material.

    /// #0E0E10 — window background (furthest back).
    static let surfaceBase = Color(red: 0.055, green: 0.055, blue: 0.063)
    /// #171719 — raised band (header/toolbar) + cards. One step up from base.
    static let surfaceRaised = Color(red: 0.090, green: 0.090, blue: 0.098)
    /// #202023 — overlay (popover/HUD/inline panel). Two steps up.
    static let surfaceOverlay = Color(red: 0.125, green: 0.125, blue: 0.137)
    /// #2A2A2E — control fill (search field, segmented control).
    static let control = Color(red: 0.165, green: 0.165, blue: 0.180)
    /// #313135 — control hover.
    static let controlHover = Color(red: 0.192, green: 0.192, blue: 0.208)

    /// White α 0.92 — primary text (≈#EAEAEA, never pure white).
    static let textPrimary = Color.white.opacity(0.92)
    /// White α 0.60 — secondary text / labels.
    static let textSecondary = Color.white.opacity(0.60)
    /// White α 0.38 — tertiary text / metadata / disabled.
    static let textTertiary = Color.white.opacity(0.38)

    // MARK: - Graphite Matte surface ladder
    /// Window background (furthest back).
    static let mtCanvas = adaptive(light: 0xf5f5f7, dark: 0x0d0d0f)
    /// Cards, panels, and the capsule body.
    static let mtRaise = adaptive(light: 0xffffff, dark: 0x16161a)
    /// Nested controls and selected rows.
    static let mtRaise2 = adaptive(light: 0xe8e8ed, dark: 0x1b1b20)
    /// Hairline dividers and borders.
    static let mtLine = adaptive(light: 0xd2d2d7, dark: 0x232329)
    /// Stronger hairline for focus and capsule edges.
    static let mtLine2 = adaptive(light: 0x8e8e93, dark: 0x2c2c34)

    // MARK: - Liquid Glass (floating recorder family)
    //
    // The capsule, the ping, the review editor, the palette and the quick-add
    // panel are made of the PLATFORM material (macOS 26 `.glassEffect`). The
    // material itself is UNTINTED — Liquid Glass has no inherent colour and
    // takes it from the content behind it. These tokens only describe what
    // rides ON the material. Consumed only by `.sottoGlass(_:in:)` — see
    // `SottoGlass.swift`.

    /// A control riding on glass (esc hint, retry, key cap, version segment).
    /// A light lift, not a second sheet of glass: white on dark glass, black on
    /// light glass, both low enough to stay part of the material. The dark side
    /// needs the higher alpha because glass already runs bright there.
    static let glassChipFill = adaptive(light: 0x000000, lightAlpha: 0.06,
                                        dark: 0xffffff, darkAlpha: 0.12)

    /// Alpha of the transcript scrim. Capped well below an opaque frost: the
    /// glass owns legibility, the scrim only settles a long stretch of text.
    static let glassScrimAlpha: Double = 0.22

    /// A soft recess behind a long stretch of transcript text — pushes the
    /// backdrop toward the appearance's own ground so the ink settles on it.
    static let glassScrim = adaptive(light: 0xffffff, dark: 0x000000)
        .opacity(glassScrimAlpha)

    /// Alpha of the stained-glass tint on a terminal capsule state. Colour on
    /// glass is reserved for status, and stays faint enough that the material
    /// still reads as glass rather than as a coloured slab.
    static let glassStateTintAlpha: Double = 0.16

    /// Legibility shadow for ink sitting directly on glass. Opposes the ink, so
    /// it separates the glyphs from the desktop in either appearance.
    static let glassInkShadow = adaptive(light: 0xffffff, dark: 0x000000).opacity(0.5)

    // MARK: - Ink ladder
    static let inkPrimary = adaptive(light: 0x1d1d1f, dark: 0xe7e7ea)
    static let inkSecondary = adaptive(light: 0x515157, dark: 0x9a9aa2)
    /// Large-text, graphical, disabled, and decorative use only.
    static let inkTertiary = adaptive(light: 0x6e6e73, dark: 0x6d6d78)

    /// Foreground for solid accent fills.
    static let onAccent = adaptive(light: 0xffffff, dark: 0x0d0d0f)

    // MARK: - Brand accent — user-selectable (default phosphor lime #b9f27e)
    /// The "signal" accent. Resolves the stored `AccentStore` choice so every
    /// existing call site follows the user's accent without changes; window
    /// roots observe `AccentStore` for live updates.
    static var phosphor: Color { AccentStore.shared.choice.color }

    // MARK: - State colors (4 functional now; syntax hues kept, wired at P12)
    /// Recording signal (Dark #ff5a52).
    static let stateRecord = adaptive(light: 0xb42318, dark: 0xff5a52)
    /// Processing signal (Dark #7fb4ff).
    static let stateProcessing = adaptive(light: 0x005ea8, dark: 0x7fb4ff)
    /// Commit signal (Dark #8af06e).
    static let stateCommit = adaptive(light: 0x2f6f1d, dark: 0x8af06e)
    /// Failure signal (Dark #ffb86b).
    static let stateFail = adaptive(light: 0x8a4b00, dark: 0xffb86b)
    // Deferred syntax hues (kept in token file, activated at P12 — NOT used in Wave A):
    /// #c46bf0 — keyword-violet (enhance, P12).
    static let synEnhance = Color(red: 0xc4/255.0, green: 0x6b/255.0, blue: 0xf0/255.0)

    // MARK: - Halo intensity
    enum HaloIntensity {
        case soft   // 0.18 — recording at low audio
        case medium // 0.22 — transcribing
        case strong // 0.28 — enhancing breathing peak

        var alpha: CGFloat {
            switch self {
            case .soft:   return 0.18
            case .medium: return 0.22
            case .strong: return 0.28
            }
        }
    }
}

extension Color {
    /// Multiplies the color by `alpha`. Convenience over `.opacity` to keep call sites terse.
    func a(_ alpha: Double) -> Color { self.opacity(alpha) }
}
