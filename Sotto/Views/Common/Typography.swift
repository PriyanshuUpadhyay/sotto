import SwiftUI

extension View {
    /// Numeric readout: SF Pro with tabular (monospaced) DIGITS only — keeps
    /// columns aligned without the "terminal" feel of a fully monospaced font.
    func tabularNumbers() -> some View { self.monospacedDigit() }
}

extension Font {
    /// UI chrome face that FOLLOWS the user's text-size setting. Renders the
    /// system UI font exactly as `.system(size:weight:)` does at the default
    /// size, but scales with Larger Text because it is anchored to a text
    /// style. Every fixed `.system(size:)` on a LABEL should be this instead;
    /// glyph sizes inside fixed frames stay fixed.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular,
                   relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(".AppleSystemUIFont", size: size, relativeTo: style).weight(weight)
    }

    /// The Sotto wordmark face — the ONLY place full monospaced is allowed.
    static func wordmark(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    /// SF Mono for ALL machine data — timestamps, latency, error codes,
    /// metadata key/values, ⌘K input, partial transcripts, hotkey chips.
    /// Small data (≤14px) must use `Palette.inkSecondary`, NOT `inkTertiary`
    /// (P0 contrast: inkTertiary fails small-text AA).
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// SF Mono microlabel face (callers add `.tracking(0.14...0.22 em)` +
    /// `.textCase(.uppercase)`). Color: `Palette.inkSecondary` for the typical
    /// small (≤14px) microlabel — `inkTertiary` is large-text/graphical only
    /// and fails small-text AA on matte (P0 decision).
    static func microlabel(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    /// New York serif for the USER'S OWN WORDS — live partial transcripts,
    /// history transcript bodies, the review editor. Spoken words read as
    /// writing, not machine output (2026-07 revamp spec, design-mockups/).
    /// Mono stays reserved for machine data; UI chrome stays SF Pro.
    static func transcript(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
