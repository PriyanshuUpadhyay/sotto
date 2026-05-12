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
/// - `Palette.accent` / `accentMuted` / `accentGlow` retained as the legacy
///   tangerine (#FF5B3A) so out-of-scope call sites (Settings / Metrics /
///   History / etc.) keep compiling *and* the existing `PaletteTests`
///   regression guard stays green. This foundation milestone owns only
///   HUD-adjacent code under `VoiceInk/Views/Recorder/**` + Palette.swift
///   itself; the SETTINGS pair migrates remaining call sites to `brandAcid`.
/// - `Palette.success` only for true completion / validation success.
/// - `Palette.hairline` / `hairlineSoft` for glass borders.
/// - `Palette.innerHi` for the top-edge sheen on glass surfaces.
enum Palette {
    /// #30D158 — mid-saturation green. Reads positive without lab-green shock.
    static let success = Color(red: 0.188, green: 0.820, blue: 0.345)

    /// #FF9F0A — amber. Power Mode signal.
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

    /// #FF5B3A — legacy tangerine accent. Retained verbatim so out-of-scope
    /// call sites under Settings / Metrics / History / etc. keep compiling
    /// *and* the existing `PaletteTests.accentTokenHasExpectedHex` regression
    /// guard stays green. Migration to `brandAcid` happens in the SETTINGS
    /// pair (post-foundation milestone). HUD-adjacent surfaces consume
    /// `brandAcid` directly; do NOT use `accent` for new Sotto surfaces.
    static let accent = Color(red: 1.000, green: 0.357, blue: 0.227)

    /// #FF5B3A α 0.42 — legacy muted accent fill. See `accent` for migration note.
    static let accentMuted = Color(red: 1.000, green: 0.357, blue: 0.227).opacity(0.42)

    /// #FF5B3A α 0.55 — legacy accent glow. See `accent` for migration note.
    static let accentGlow = Color(red: 1.000, green: 0.357, blue: 0.227).opacity(0.55)

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
