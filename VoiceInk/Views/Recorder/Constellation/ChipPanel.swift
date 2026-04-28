import SwiftUI

// MARK: - ChipDescriptor
//
// Value-type spec for one chip slot in the cluster. Built per-state by the
// factories in `ClusterChips.swift`; rendered by `ChipPanel`. Carries side +
// motion + content so layout, motion, and content stay decoupled.

struct ChipDescriptor: Identifiable {
    enum Kind { case anchor, secondary, action }
    enum Side { case left, right }
    enum Motion { case none, ringPulseFast, ringPulseSlow, shimmer, breath }
    enum Row { case primary, action }

    let id: String
    let kind: Kind
    let side: Side
    let motion: Motion
    let row: Row
    let view: AnyView

    /// VoiceOver label. Empty string → chip is decorative-hidden.
    let axLabel: String

    init<V: View>(
        id: String,
        kind: Kind = .secondary,
        side: Side = .right,
        motion: Motion = .none,
        row: Row = .primary,
        axLabel: String,
        @ViewBuilder view: () -> V
    ) {
        self.id = id
        self.kind = kind
        self.side = side
        self.motion = motion
        self.row = row
        self.axLabel = axLabel
        self.view = AnyView(view())
    }
}

// MARK: - ChipPanel
//
// Lays out a list of `ChipDescriptor`. Single-row default: anchor in middle,
// secondaries fan out by `side`. Two-row mode (`hasActionRow == true`) adds
// a second row below for action chips — only used by the failed state.
//
// Spec §2 geometry: 8pt spacing between chips. Anchor chip is mounted whether
// or not it carries motion — motion attaches inside the chip view itself.

struct ChipPanel: View {
    let phase: ClusterPhase
    let chips: [ChipDescriptor]

    var body: some View {
        let primary = chips.filter { $0.row == .primary }
        let actions = chips.filter { $0.row == .action }
        let hasActionRow = !actions.isEmpty

        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(primary.filter { $0.side == .left }.reversed()) { chip in
                    chipView(chip)
                }
                ForEach(primary.filter { $0.kind == .anchor }) { chip in
                    chipView(chip)
                }
                ForEach(primary.filter { $0.side == .right && $0.kind != .anchor }) { chip in
                    chipView(chip)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(combinedAxLabel(for: primary))

            if hasActionRow {
                HStack(spacing: 8) {
                    ForEach(actions) { chip in
                        chipView(chip)
                            .accessibilityLabel(chip.axLabel)
                    }
                }
            }
        }
    }

    /// Spec §6 VoiceOver order — anchor → reason → secondaries — follows the
    /// chip array order, NOT the rendered HStack order (anchor sits visually
    /// centred between left/right secondaries). Joining in array order keeps
    /// the spec contract regardless of layout. Action chips are excluded —
    /// they remain individually focusable buttons in the second row.
    private func combinedAxLabel(for chips: [ChipDescriptor]) -> String {
        chips
            .map(\.axLabel)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    @ViewBuilder
    private func chipView(_ chip: ChipDescriptor) -> some View {
        chip.view
            .id(chip.id)
            .transition(Self.chipTransition)
    }

    private static let chipTransition: AnyTransition = .asymmetric(
        insertion: AnyTransition.opacity.animation(Animation.haloExpand),
        removal: AnyTransition.opacity.animation(Animation.clusterFade)
    )
}
