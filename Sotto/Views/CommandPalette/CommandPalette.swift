import SwiftUI
import AppKit

/// Centered Graphite-Matte command card. Search field on top; fuzzy-ranked rows
/// below; ↑↓ move · ⏎ run · ⎋ close. Consumes the matte foundation tokens
/// (`Palette.mt*` surfaces, `inkPrimary/inkSecondary`, `Font.mono`); `phosphor`
/// is the signal — reserved for the selected row glyph. Floating + shadowed (it
/// is a floating object). Hosted inside an NSPanel by `CommandPaletteController`;
/// `onRun`/`onClose` are supplied by the controller. `onRun`'s Bool is whether ⌘
/// was held (transcript rows: plain → enhanced, ⌘ → raw); other categories
/// ignore it.
struct CommandPalette: View {
    @ObservedObject var model: CommandPaletteModel
    let onRun: (PaletteCommand, Bool) -> Void
    let onClose: () -> Void
    /// Re-sources the model for a new query (the controller re-fetches matching
    /// transcripts). Nil in previews/snapshots, which drive a fixed source.
    var onQueryChanged: ((String) -> Void)?

    @State private var query: String = ""
    @State private var expanded: Set<String> = []
    @FocusState private var searchFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    private let card = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)

    private var borderColor: Color {
        A11y.borderColor(increaseContrast: contrast == .increased)
    }

    /// The card floats, so it keeps a drop shadow — but the dark-tuned opacity
    /// reads as a grey smudge under the light `mtRaise`.
    private var cardShadow: Color {
        .black.opacity(colorScheme == .dark ? 0.5 : 0.18)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(Palette.mtLine)
            results
            footer
        }
        .frame(width: 560)
        .background(Palette.mtRaise, in: card)
        .overlay(card.stroke(borderColor, lineWidth: 1))
        .shadow(color: cardShadow, radius: 30, y: 14)
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Palette.inkSecondary)
            TextField("Search commands…", text: $query)
                .textFieldStyle(.plain)
                .font(.mono(15))
                .foregroundColor(Palette.inkPrimary)
                .focused($searchFocused)
                .onSubmit { runSelected() }
                .onChange(of: query) { _, newValue in
                    // No debounce: ranking is pure and synchronous over the
                    // in-memory source, and a delay would leave ⏎ running the
                    // previous result set.
                    onQueryChanged?(newValue)
                    model.applyQuery(newValue)
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    @ViewBuilder
    private var results: some View {
        if model.results.isEmpty {
            Text("No matching commands")
                .font(.mono(13))
                .foregroundColor(Palette.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 72)
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { idx, cmd in
                        row(cmd, selected: idx == model.selectionIndex)
                            .id(idx)
                            .contentShape(Rectangle())
                            .onTapGesture { onRun(cmd, NSEvent.modifierFlags.contains(.command)) }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 360)
            .onChange(of: model.selectionIndex) { _, idx in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(idx, anchor: .center) }
            }
        }
    }

    private func row(_ cmd: PaletteCommand, selected: Bool) -> some View {
        let isExpanded = expanded.contains(cmd.id)
        // Rows are inset 6pt from the card, so a concentric inner radius keeps
        // the corners parallel.
        let rowShape = RoundedRectangle(cornerRadius: Radius.inner(of: Radius.panel, inset: 6),
                                        style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                // phosphor is the signal — only the selected row's glyph lights up.
                Image(systemName: cmd.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(selected ? Palette.phosphor : Palette.inkSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cmd.title)
                        .font(.system(size: 14))
                        .foregroundColor(Palette.inkPrimary)
                        .lineLimit(1)
                }
                Spacer()
                // Transcript rows expand in place to reveal the full text. The
                // chevron is its own tap target so it toggles WITHOUT pasting
                // (the row-level tap that runs the command lives one level up).
                if cmd.transcript != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Palette.inkSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleExpanded(cmd.id) }
                }
                // Right-aligned mono category hint (the row's machine-data label).
                Text(cmd.category.label)
                    .font(.mono(11))
                    .foregroundColor(Palette.inkSecondary)
            }
            .frame(height: 40)

            if isExpanded, let item = cmd.transcript {
                // Preview the text plain ⏎ will paste (enhanced, raw fallback) so
                // the preview matches the default action; ⌘⏎ still pastes raw.
                Text(CommandRegistry.transcriptPasteText(item: item, useEnhanced: true))
                    .font(.mono(12))
                    .foregroundColor(Palette.inkSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 34)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 12)
        .background(rowShape.fill(selected ? Palette.mtRaise2 : Color.clear))
        .overlay(
            // Inset hairline on the selected row (matches the rail/list grammar).
            rowShape.inset(by: 0.5).stroke(selected ? Palette.mtLine2 : Color.clear, lineWidth: 1)
        )
    }

    private func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            hint("↑↓", "move"); hint("⏎", "select"); hint("⌘⏎", "raw"); hint("⎋", "close")
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Palette.mtRaise2.opacity(0.6))
        .overlay(Divider().overlay(Palette.mtLine), alignment: .top)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.mono(11, weight: .semibold)).foregroundColor(Palette.inkPrimary)
            Text(label).font(.mono(11)).foregroundColor(Palette.inkSecondary)
        }
    }

    private func runSelected() {
        if let cmd = model.selectedCommand {
            onRun(cmd, NSEvent.modifierFlags.contains(.command))
        }
    }
}
