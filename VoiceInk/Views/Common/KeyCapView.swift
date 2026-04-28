import SwiftUI

// MARK: - KeyCapView
//
// 24×24pt mono glass cap rendering a single key glyph (⌘, ⇧, ⌥, ⌃, fn, V…).
// Glass background reuses `HaloMaterial` at `.hidden` phase so the surface
// renders as the standard onyx/light glass without any state-keyed halo.
// Spec §3.3 — used by `KeyCombo` for hotkey display in Settings.
//
// Reviewer focus (plan §P2.E): glyphs are Unicode key symbols (⌘, ⇧, ⌥, ⌃),
// NOT custom SF Symbols. Pass the symbol verbatim — the cap renders it in
// SF Mono medium 11pt with 4pt internal padding so the centered glyph reads
// correctly even on narrow keys ("V") and wider tokens ("fn").

struct KeyCapView: View {
    let key: String
    var appearance: GlassAppearance

    init(_ key: String, appearance: GlassAppearance = .onyx) {
        self.key = key
        self.appearance = appearance
    }

    var body: some View {
        ZStack {
            // Glass background — `.hidden` phase = no state halo, just the
            // material's base fill + gloss + inner stroke. RoundedRectangle
            // 6pt corner radius per spec §3.3.
            HaloMaterial(
                shape: RoundedRectangle(cornerRadius: 6, style: .continuous),
                phase: .hidden,
                appearance: appearance
            )

            // Key glyph — SF Mono medium 11pt. `.monospaced` design + `.medium`
            // weight resolves to SF Mono Medium. 4pt padding keeps the glyph
            // centered without clipping wider tokens like "fn".
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(textColor)
                .padding(4)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
        .frame(width: 24, height: 24)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    /// Variant-keyed glyph color — onyx 0.92 white, light 0.82 black. Tuned
    /// so mono key glyphs stay legible against both the dark and light caps.
    private var textColor: Color {
        switch appearance {
        case .onyx:  return Color.white.opacity(0.92)
        case .light: return Color.black.opacity(0.82)
        }
    }

    /// VoiceOver label — speaks the modifier name instead of the glyph so
    /// screen-reader users hear "Command Shift V" not "clover-leaf snowflake V".
    private var accessibilityLabel: String {
        switch key {
        case "⌘":  return "Command"
        case "⇧":  return "Shift"
        case "⌥":  return "Option"
        case "⌃":  return "Control"
        case "fn", "Fn", "FN": return "Function"
        case "↩", "⏎": return "Return"
        case "⌫":  return "Delete"
        case "␣":  return "Space"
        case "⎋":  return "Escape"
        case "⇥":  return "Tab"
        default:    return key
        }
    }
}

// MARK: - KeyCombo
//
// Composer view that lays out a sequence of `KeyCapView`s with 4pt spacing
// per spec §3.3. Reads as a single combined accessibility element so VO
// announces "Command Shift V" rather than three separate caps.

struct KeyCombo: View {
    let keys: [String]
    var appearance: GlassAppearance

    init(keys: [String], appearance: GlassAppearance = .onyx) {
        self.keys = keys
        self.appearance = appearance
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCapView(key, appearance: appearance)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#if DEBUG
private struct KeyCapPreviewGrid: View {
    let appearance: GlassAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("KeyCap — \(appearance == .onyx ? "Onyx" : "Light")")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                KeyCapView("⌘", appearance: appearance)
                KeyCapView("⇧", appearance: appearance)
                KeyCapView("⌥", appearance: appearance)
                KeyCapView("⌃", appearance: appearance)
                KeyCapView("fn", appearance: appearance)
                KeyCapView("V", appearance: appearance)
            }

            Divider()

            KeyCombo(keys: ["⌘", "⇧", "V"], appearance: appearance)
            KeyCombo(keys: ["⌃", "⌥", "Space"], appearance: appearance)
            KeyCombo(keys: ["⌥"], appearance: appearance)
        }
        .padding(40)
    }
}

#Preview("Onyx") {
    KeyCapPreviewGrid(appearance: .onyx)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Light") {
    KeyCapPreviewGrid(appearance: .light)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
