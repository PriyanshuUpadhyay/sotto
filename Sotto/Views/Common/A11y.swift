import SwiftUI

/// The non-color state cue (council change #5: states must be distinguishable
/// WITHOUT hue) + VoiceOver labels. Shared by HUD capsule, icon rail, inspector.
///
/// The SF Symbol *is* the shape cue — each state maps to a structurally distinct
/// glyph (ring vs. gear vs. check vs. triangle), so the set reads correctly for
/// color-blind users and in high-contrast/grayscale without a parallel shape
/// token. Callers pair the glyph with `Palette.*` only as a redundant signal.
enum StateCue {
    /// Distinct, non-color SF Symbol per state.
    static func glyph(for s: CapsuleState) -> String {
        switch s {
        case .idleReady:  return "waveform"                // armed/ready
        case .recording:  return "record.circle"           // sacred red dot + ring
        case .processing: return "sparkles"                // transcribe+enhance
        case .commit:     return "checkmark.circle"
        case .fail:       return "exclamationmark.triangle"
        }
    }
    /// Spoken VoiceOver label per state. `.processing` covers both pipeline
    /// steps — `enhancing` picks the one actually running; `.fail` names the
    /// recovery the capsule actually offers (⌘R retries, except when no model
    /// is installed and only Settings can help).
    static func voiceOverLabel(for s: CapsuleState, enhancing: Bool = false,
                               failureRetryable: Bool = true) -> String {
        switch s {
        case .idleReady:  return "Ready to record"
        case .recording:  return "Recording"
        case .processing: return enhancing ? "Enhancing" : "Transcribing"
        case .commit:     return "Pasted"
        case .fail:
            return failureRetryable
                ? "Failed. Press Command R to retry."
                : "Failed. No transcription model installed. Open Settings."
        }
    }
}

enum A11y {
    /// Hairline color that strengthens under Increase Contrast so edges stay
    /// visible.
    static func borderColor(increaseContrast: Bool) -> Color {
        increaseContrast ? Palette.mtLine2 : Palette.mtLine
    }
}
