import SwiftUI
import SwiftData
import AppKit

// MARK: - ReviewTray
//
// The post-paste PING — a minimal 38pt capsule pill (hosted by
// `ReviewTrayWindowManager`) confirming the paste into the frontmost app:
// commit-green ✓ + `PASTED → <APP>`. Ephemeral: holds ~1.5s then fades out;
// hover (or the panel becoming key) pauses the auto-dismiss and reveals two
// quiet ghost actions — Undo · Copy.
//
// Reveal motion: the pill is LAID OUT at full width (glyph + caption + actions)
// and the collapsed state clips the actions off with an animated trailing mask
// inset + a translate that recenters the visible portion — paint-only, never an
// animated `.frame(width:)` (mockup 03's clip-path technique).
//
// Undo = restore the prior clipboard ONLY (NOT a synthetic ⌘Z; the pasted text
// stays in the target app). Copy = put the pasted text back on the clipboard
// non-transiently.
//
// The panel is `.nonactivatingPanel`, so merely SHOWING it does not steal focus
// from the user's app — focus moves only on an explicit click.

struct ReviewTray: View {
    @ObservedObject var manager: ReviewTrayWindowManager
    /// Main-context handle for the most-recent-`Transcription` query (the row
    /// that was just pasted) — the Copy fallback when `CursorPaster`'s stash is
    /// empty. The host window manager threads `engine.modelContext` in.
    let modelContext: ModelContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var appName = ""
    @State private var hovered = false
    /// Trailing mask inset that hides the actions when collapsed: measured
    /// actions width + the pill's 8pt gap (mockup 03's `--clip`).
    @State private var actionsClip: CGFloat = 0
    /// The discovery window has passed, so the pill may collapse to the
    /// caption. Undo is the only reversal Sotto offers — it starts revealed
    /// rather than waiting for a pointer that may never arrive.
    @State private var discoveryElapsed = false

    private var revealed: Bool { hovered || manager.isPanelKey || !discoveryElapsed }

    var body: some View {
        pill
            .onChange(of: manager.currentEvent, initial: true) { _, event in
                guard let event else { return }
                appName = event.appName
                hovered = false
            }
            .task(id: manager.currentEvent) {
                discoveryElapsed = false
                try? await Task.sleep(for: .seconds(MotionTokens.committedHold))
                guard !Task.isCancelled else { return }
                discoveryElapsed = true
            }
    }

    // MARK: - Pill

    private static let pillHeight: CGFloat = 38

    private var pill: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.capsule, style: .continuous)
        return HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.stateCommit)
                .glassInkShadow()
            caption
            actions
                .opacity(revealed ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.pillHeight)
        // Same glass as the capsule — the ping is the capsule's sibling, not a
        // different kind of object. Material, top edge and inner shadow all
        // live in `.sottoGlass`.
        .sottoGlass(.capsule, in: shape)
        .overlay(
            shape.strokeBorder(A11y.borderColor(increaseContrast: contrast == .increased), lineWidth: 1)
        )
        .compositingGroup()
        .mask(alignment: .leading) {
            shape.padding(.trailing, revealed ? 0 : actionsClip)
        }
        // Commit green bleeds through the glass — outside the mask, which would
        // otherwise crop the glow away.
        .sottoGlassGlow(Palette.stateCommit, level: .capsule)
        // Recenter the collapsed visible portion within the full-width panel.
        .offset(x: revealed ? 0 : actionsClip / 2)
        .animation(reduceMotion ? nil : MotionTokens.stateEnter, value: revealed)
        .background(sizeReader)
        .onHover { hovered = $0; manager.hoverChanged($0) }
        .onExitCommand { manager.dismiss() }
    }

    /// Reports the pill's FULL (unmasked) fitting size to the manager so the
    /// panel is sized for the expanded content once — the reveal never resizes
    /// the panel.
    private var sizeReader: some View {
        GeometryReader { geo in
            Color.clear.preference(key: TraySizeKey.self, value: geo.size)
        }
        .onPreferenceChange(TraySizeKey.self) { manager.contentSizeChanged($0) }
    }

    private var caption: some View {
        HStack(spacing: 4) {
            Text("PASTED")
                .foregroundColor(Palette.inkSecondary)
            Text("\u{2192}")
                .foregroundColor(Palette.phosphor)
            Text(appName)
                .foregroundColor(Palette.inkSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.microlabel(10))
        .tracking(1.1)
        .textCase(.uppercase)
        .glassInkShadow()
    }

    // MARK: - Ghost actions (hover/focus reveal)

    /// VoiceOver announces these; the pill paints them uppercased.
    static let undoButtonLabel = "Undo"
    static let copyButtonLabel = "Copy"

    private var actions: some View {
        HStack(spacing: 6) {
            ghostButton(icon: "arrow.uturn.backward", label: Self.undoButtonLabel) { undo() }
            ghostButton(icon: "doc.on.doc", label: Self.copyButtonLabel) { copy() }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            actionsClip = $0 + 8
        }
    }

    private func ghostButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label.uppercased())
                    .font(.microlabel(10))
                    .tracking(1.1)
            }
            .foregroundColor(Palette.inkSecondary)
            .glassInkShadow()
            .padding(.horizontal, 6)
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(PressableChipStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Data

    /// The text that was actually pasted — drives Copy. Prefers the exact
    /// last-pasted text stashed by `CursorPaster`; falls back to the most-recent
    /// `Transcription`'s enhanced/raw text.
    private var pastedText: String? {
        if let text = CursorPaster.lastPastedText, !text.isEmpty { return text }
        guard let t = RecentTranscriptionQuery.mostRecent(in: modelContext) else { return nil }
        if let enhanced = t.enhancedText, !enhanced.isEmpty { return enhanced }
        return t.text
    }

    // MARK: - Actions

    private func undo() {
        CursorPaster.restorePriorClipboard()
        manager.dismiss()
    }

    private func copy() {
        if let text = pastedText { CursorPaster.copyToClipboard(text) }
        manager.dismiss()
    }
}

// MARK: - TraySizeKey
// Reports the rendered pill size up to `ReviewTrayWindowManager` so the panel
// is sized to fit the full (expanded) content.
private struct TraySizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - RecentTranscriptionQuery
//
// Most-recent `Transcription` lookup — the row the app just pasted (the paste
// path inserts + saves it immediately before posting the `PasteEvent`). Pure
// over an injected `ModelContext` so it is unit-testable against an in-memory
// container.

enum RecentTranscriptionQuery {
    static func mostRecent(in context: ModelContext) -> Transcription? {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
