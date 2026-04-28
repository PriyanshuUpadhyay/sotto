import SwiftUI

/// Functional accents for VoiceInk UI. Single live-state accent (`accent`)
/// post-redesign 2026-04 — `success` (green), `warn` (amber), `neutral` (gray)
/// retained for non-state semantics. Source of truth:
/// `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1.
///
/// Usage:
/// - `Palette.accent` for any live state (recording / transcribing /
///   enhancing / failed). Motion distinguishes states, not color.
/// - `Palette.accentMuted` for chip backgrounds (~0.16-0.42 alpha range).
/// - `Palette.accentGlow` for ringPulse shadow stops.
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

    /// #FF5B3A — single live-state accent (locked, post-redesign 2026-04). All
    /// "live" surfaces — recording, transcribing, enhancing, failed — use this
    /// one accent; motion (ringPulse / shimmer / breath) distinguishes states,
    /// not color. Source of truth: docs/superpowers/specs/2026-04-28-aesthetic-redesign.md §1.
    static let accent = Color(red: 1.000, green: 0.357, blue: 0.227)

    /// #FF5B3A α 0.42 — for muted accent fills (chip backgrounds, halo bases).
    static let accentMuted = Color(red: 1.000, green: 0.357, blue: 0.227).opacity(0.42)

    /// #FF5B3A α 0.55 — for accent glows (ringPulse end frames, shadow tints).
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
