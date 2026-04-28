import SwiftUI

/// Functional accents for VoiceInk UI. Six tokens — kept tight on purpose.
/// Source of truth: `docs/UX_IMPL_NOTES.md` §4 (palette rationale).
///
/// Usage:
/// - `Palette.recording` etc. as base colors. Apply alpha at the call site.
/// - Halo (CALayer shadow): 0.20–0.32 alpha typical.
/// - Chip background: ~0.16 alpha.
/// - Glyph / dot foreground: 1.0.
enum Palette {
    /// #FF3B30 — system-red intent, pinned to a stable hex (avoids `Color.red` shifts under Beta themes).
    static let recording = Color(red: 1.00, green: 0.231, blue: 0.188)

    /// #5AC8FA — Apple cyan. Distinct from recording without competing.
    static let transcribe = Color(red: 0.353, green: 0.784, blue: 0.980)

    /// #BF5AF2 — "AI" violet. Differentiates machine-shaping from machine-listening.
    static let enhance = Color(red: 0.749, green: 0.353, blue: 0.949)

    /// #30D158 — mid-saturation green. Reads positive without lab-green shock.
    static let success = Color(red: 0.188, green: 0.820, blue: 0.345)

    /// #FF9F0A — amber. Power Mode signal.
    static let warn = Color(red: 1.00, green: 0.624, blue: 0.039)

    /// #8E8E93 — system gray. Idle baseline.
    static let neutral = Color(red: 0.557, green: 0.557, blue: 0.576)

    /// #0F0F12-ish — onyx backdrop tone for the cinematic walkthrough host
    /// and other dark-mode surfaces that anchor a `.onyx` GlassCard. Matches
    /// the previously-hardcoded `Color(red: 0.06, green: 0.06, blue: 0.07)`.
    static let onyxBackground = Color(red: 0.06, green: 0.06, blue: 0.07)

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
