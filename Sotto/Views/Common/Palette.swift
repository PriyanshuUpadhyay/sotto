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
    /// #30D158 — mid-saturation green. Reads positive without lab-green shock.
    static let success = Color(red: 0.188, green: 0.820, blue: 0.345)

    /// #FF9F0A — amber. Warning signal.
    static let warn = Color(red: 1.00, green: 0.624, blue: 0.039)

    /// #8E8E93 — system gray. Idle baseline.
    static let neutral = Color(red: 0.557, green: 0.557, blue: 0.576)

    /// #0F0F12-ish — onyx backdrop tone for the cinematic walkthrough host
    /// and other dark-mode surfaces that anchor a `.onyx` GlassCard. Matches
    /// the previously-hardcoded `Color(red: 0.06, green: 0.06, blue: 0.07)`.
    /// Kept transitionally; AppDelegate host migrates to `onyxBg` in W4.
    static let onyxBackground = Color(red: 0.06, green: 0.06, blue: 0.07)

    /// #D4FF3A (`0xD4FF3A`) — Acid Lime brand accent (Sotto). Wordmark stop,
    /// selected row, section labels, prompt glyph, CTA halo, HUD audio bars.
    /// Source of truth: spec §1.4. Single source of truth — no inline hex
    /// permitted at call sites; consume via `Palette.brandAcid`.
    static let brandAcid = Color(red: 0xD4 / 255.0, green: 0xFF / 255.0, blue: 0x3A / 255.0)

    /// `brandAcid` α 0.42 — muted lime fill (chip backgrounds, halo bases).
    static let brandAcidMuted = brandAcid.opacity(0.42)

    /// `brandAcid` α 0.55 — lime glow (halo end frames, shadow tints).
    static let brandAcidGlow = brandAcid.opacity(0.55)

    /// #FF3B30 — recording dot + fail state (spec §4.2).
    static let recRed = Color(red: 1.000, green: 0.231, blue: 0.188)

    /// #30D158 — committed (post-paste) halo. Named alias for spec §4.2 parity;
    /// shares the value with `success`.
    static let commitGreen = success

    /// #5AC8FA — transcribing sweep + capsule border (spec §4.2).
    static let transCyan = Color(red: 0.353, green: 0.784, blue: 0.980)

    /// #BF5AF2 — enhancing halo breath + arc spin (spec §4.2).
    static let enhViolet = Color(red: 0.749, green: 0.353, blue: 0.949)

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

    // MARK: - Graphite Matte surface ladder (dark-only, v1)
    /// #0d0d0f — window background (furthest back).
    static let mtCanvas = Color(red: 0x0d/255.0, green: 0x0d/255.0, blue: 0x0f/255.0)
    /// #16161a — cards, panels, capsule body.
    static let mtRaise  = Color(red: 0x16/255.0, green: 0x16/255.0, blue: 0x1a/255.0)
    /// #1b1b20 — nested controls, selected rows.
    static let mtRaise2 = Color(red: 0x1b/255.0, green: 0x1b/255.0, blue: 0x20/255.0)
    /// #232329 — hairline dividers / borders.
    static let mtLine   = Color(red: 0x23/255.0, green: 0x23/255.0, blue: 0x29/255.0)
    /// #2c2c34 — stronger hairline (focus, capsule edge).
    static let mtLine2  = Color(red: 0x2c/255.0, green: 0x2c/255.0, blue: 0x34/255.0)

    // MARK: - Ink ladder
    /// #e7e7ea — primary text.
    static let inkPrimary   = Color(red: 0xe7/255.0, green: 0xe7/255.0, blue: 0xea/255.0)
    /// #9a9aa2 — labels, secondary. Also the grade for small mono metadata +
    /// microlabels (clears 4.5:1 text-AA on every matte surface; P0 decision).
    static let inkSecondary = Color(red: 0x9a/255.0, green: 0x9a/255.0, blue: 0xa2/255.0)
    /// #6d6d78 — idle/disabled/decorative + LARGE-TEXT/graphical only (< 4.5:1
    /// on matte → NEVER body copy or small metadata; P0 contrast report).
    static let inkTertiary  = Color(red: 0x6d/255.0, green: 0x6d/255.0, blue: 0x78/255.0)

    // MARK: - Brand accent — user-selectable (default phosphor lime #b9f27e)
    /// The "signal" accent. Resolves the stored `AccentStore` choice so every
    /// existing call site follows the user's accent without changes; window
    /// roots observe `AccentStore` for live updates.
    static var phosphor: Color { AccentStore.shared.choice.color }

    // MARK: - State colors (4 functional now; syntax hues kept, wired at P12)
    /// #ff5a52 — recording (SACRED red).
    static let stateRecord     = Color(red: 0xff/255.0, green: 0x5a/255.0, blue: 0x52/255.0)
    /// #7fb4ff — processing (transcribe+enhance, single working hue for now).
    static let stateProcessing = Color(red: 0x7f/255.0, green: 0xb4/255.0, blue: 0xff/255.0)
    /// #8af06e — commit.
    static let stateCommit     = Color(red: 0x8a/255.0, green: 0xf0/255.0, blue: 0x6e/255.0)
    /// #ffb86b — fail.
    static let stateFail       = Color(red: 0xff/255.0, green: 0xb8/255.0, blue: 0x6b/255.0)
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
