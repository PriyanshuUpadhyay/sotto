import SwiftUI

// MARK: - ConstellationChip (legacy)
//
// Pre-W2 PROVIDER · MODEL capsule. Retained ONLY for `CinematicWalkthrough.swift`
// (onboarding, deferred per spec §5). The live recorder uses chip factories
// in `ClusterChips.swift`. Do not add new consumers.
//
// Glass capsule with color dot + mono provider/model identifier. Sits right-of-notch
// in the Constellation recorder layout (spec §3.1, plan §P1.E).
//
// Stateless view — inputs are caller-provided strings. Orchestrator (P1.G) wires
// them from `aiService.selectedAIProvider` + `aiService.currentModel`. Visibility,
// dot color, and outer halo are all derived from `phase`.
//
// Layout (spec §3.1):
//   • 20pt height, intrinsic width, 10pt corner radius (Capsule).
//   • L→R: 5pt color dot + 4pt gap + mono label "PROVIDER · MODEL".
//
// Typography (spec §2.2 — mono identity):
//   • SF Mono, medium, 9pt, all-caps, tracked +0.12em ≈ `tracking(1.4)` in SwiftUI.
//
// Glass body: `HaloMaterial(shape: Capsule(), phase:, appearance:)` — never a
// one-off `Color.black.opacity(0.78)` shortcut (plan reviewer focus).
//
// Halo: extra outer box-shadow color-keyed to state, alpha 0.30–0.40 (spec §3.1)
// stacked above the material's intrinsic glow so the chip reads brighter than the
// orb at the same phase.
//
// Visibility: hidden during `.hidden`, `.armed`. Visible during `.recording`,
// `.liveText`, `.transcribing`, `.enhancing`, `.done`, `.failed`. Width morphs
// on label change via `.haloExpand` so provider/model swaps mid-flight don't
// flicker layout (plan §P1.E risk mitigation).
//
// Accessibility (spec §6.4): VoiceOver label "Provider Claude, model Sonnet 4.6".
// Dot is decorative — `accessibilityHidden(true)`. Element-level hidden when not
// visible so screen-reader users don't get a phantom chip announcement.

struct ConstellationChip: View {
    let phase: HaloPhase
    /// Caller-provided provider identifier — typically all-caps (e.g. `"CLAUDE"`).
    let providerLabel: String
    /// Caller-provided model identifier — typically all-caps + dashed (e.g. `"SONNET-4-6"`).
    let modelLabel: String
    /// Glass variant. Plumbed through to `HaloMaterial` so the chip tracks the
    /// active surface (onyx default, light when wallpaper luminance > 0.6).
    var appearance: GlassAppearance = .onyx

    // MARK: - Visibility

    /// Visible during the active phases per plan §P1.E. `.liveText` is treated
    /// as a recording sub-state (recording + partial transcript) so the chip
    /// remains lit through the streaming-caret view.
    private var isVisible: Bool {
        switch phase {
        case .hidden, .armed:
            return false
        case .recording, .liveText, .transcribing, .enhancing, .done, .failed:
            return true
        }
    }

    // MARK: - Halo intensity (spec §3.1)
    //
    // Chip-specific outer halo, distinct from `HaloMaterial`'s intrinsic glow.
    // Spec calls 0.30–0.40 alpha range; assigned per-phase so enhancing reads
    // brightest (the AI moment) and recording sits at the floor.

    private var haloAlpha: Double {
        switch phase {
        case .recording, .liveText: return 0.30
        case .transcribing:         return 0.32
        case .done:                 return 0.32
        case .failed:               return 0.34
        case .enhancing:            return 0.40
        case .hidden, .armed:       return 0.0
        }
    }

    // MARK: - Composed label

    /// `"PROVIDER · MODEL"` — the middle dot is U+00B7 (mirrors mockup).
    private var label: String { "\(providerLabel) · \(modelLabel)" }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 4) {
            // 5pt color dot — mirrors `phase.glowColor` so the chip and orb agree
            // on state at a glance. Soft point-glow keeps it readable on glass.
            Circle()
                .fill(phase.glowColor)
                .frame(width: 5, height: 5)
                .shadow(color: phase.glowColor.opacity(0.9), radius: 3)
                .accessibilityHidden(true)

            // SF Mono medium 9pt all-caps tracking 1.4 (spec §2.2).
            // `.medium` weight + `.monospaced` design resolves to SF Mono Medium.
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 10)
        .frame(height: 20)
        .background(
            // Glass body — capsule variant of HaloMaterial. Onyx/light flow
            // through `appearance`. NOT a one-off `Color.black.opacity(0.78)`
            // (plan reviewer focus).
            HaloMaterial(
                shape: Capsule(),
                phase: phase,
                appearance: appearance
            )
        )
        // Chip-specific outer halo per spec §3.1 — layered above the material's
        // own glow. Suppressed by going to alpha 0 when hidden so no phantom
        // shadow leaks during the visibility crossfade.
        .shadow(color: phase.glowColor.opacity(isVisible ? haloAlpha : 0), radius: 14)
        .opacity(isVisible ? 1 : 0)
        // Width morph on provider/model swap (plan §P1.E risk mitigation).
        // `.haloExpand` is the sanctioned spring per spec §2.4 — never `easeInOut`.
        .animation(.haloExpand, value: label)
        // Visibility + state crossfade — the 0.22s opacity/scale companion that
        // pairs with the orb's phase change.
        .animation(.haloPhaseCrossfade, value: phase)
        // Accessibility — single composite element; dot is decorative.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityHidden(!isVisible)
    }

    // MARK: - Variant tokens

    /// Mono label color tuned per glass variant — onyx needs a near-white at 0.92,
    /// light needs near-black at 0.82 to keep 9pt mono legible without competing
    /// with the material's inner gloss.
    private var textColor: Color {
        switch appearance {
        case .onyx:  return Color.white.opacity(0.92)
        case .light: return Color.black.opacity(0.82)
        }
    }

    /// VoiceOver phrasing per spec §6.4 line 580 + plan §P1.E line 228 — verbatim
    /// `"Provider Claude, model Sonnet 4.6"` (note the period before `6`).
    ///
    /// Input convention is dashed all-caps from the orchestrator (P1.G), e.g.
    /// `"SONNET-4-6"`. The first dash separates model family from version
    /// digits; subsequent dashes are decimal separators within the version.
    /// So "SONNET-4-6" → `"Sonnet 4.6"`, not `"Sonnet 4 6"` (which VO reads as
    /// "four six" rather than "four point six").
    private var voiceOverLabel: String {
        let provider = providerLabel.capitalized
        let parts = modelLabel.split(separator: "-", maxSplits: 1).map(String.init)
        let model: String
        switch parts.count {
        case 2:
            // First segment is the family ("SONNET"); the remainder is the
            // version, with internal dashes acting as decimal separators
            // ("4-6" → "4.6").
            let family = parts[0].capitalized
            let version = parts[1].replacingOccurrences(of: "-", with: ".")
            model = "\(family) \(version)"
        default:
            // No dash → no version segment to format. Capitalize whole token.
            model = modelLabel.capitalized
        }
        return "Provider \(provider), model \(model)"
    }
}

// MARK: - Previews

#if DEBUG
private struct ConstellationChipPreviewGrid: View {
    let appearance: GlassAppearance

    private let visiblePhases: [(HaloPhase, String)] = [
        (.recording,    "recording"),
        (.liveText,     "liveText"),
        (.transcribing, "transcribing"),
        (.enhancing,    "enhancing"),
        (.done,         "done"),
        (.failed,       "failed")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ConstellationChip — \(appearance == .onyx ? "Onyx" : "Light")")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            ForEach(Array(visiblePhases.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 16) {
                    ConstellationChip(
                        phase: pair.0,
                        providerLabel: "CLAUDE",
                        modelLabel: "SONNET-4-6",
                        appearance: appearance
                    )
                    Text(pair.1)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Width-morph sanity: longer label exercises the `.haloExpand`
            // animation hook on provider/model change.
            HStack(spacing: 16) {
                ConstellationChip(
                    phase: .enhancing,
                    providerLabel: "OPENAI",
                    modelLabel: "GPT-4O-MINI",
                    appearance: appearance
                )
                Text("longer label")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
    }
}

#Preview("Onyx — all visible phases") {
    ConstellationChipPreviewGrid(appearance: .onyx)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Light — all visible phases") {
    ConstellationChipPreviewGrid(appearance: .light)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
