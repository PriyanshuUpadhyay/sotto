import SwiftUI
import AppKit

// MARK: - ComposeReviewView
//
// The editable preview card. Onyx surface matching `ReviewTray`. Clean by
// design: header (caption) · auto-growing `MultiSelectTextView` (⌘D multi-select) · dim hint. No buttons,
// no drag handle — ⌘↵ pastes, Esc cancels, and richer actions live in the
// global ⌘K palette.
struct ComposeReviewView: View {
    @ObservedObject var manager: ComposeReviewWindowManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Auto-grows with content between `minEditorHeight` and `maxEditorHeight`;
    /// scrolls beyond the max.
    @State private var editorHeight: CGFloat = 220
    @State private var enhancingPulse = false

    static let panelWidth: CGFloat = 460
    private static let minEditorHeight: CGFloat = 200
    private static let maxEditorHeight: CGFloat = 560
    /// The editor's internal text inset + our padding, so the measured text
    /// height maps to the editor frame without clipping the last line.
    private static let editorChrome: CGFloat = 28
    /// Concentric radius for the frosted band inside the card
    /// (inner = outer − inset; the band is inset by the card's 14pt padding
    /// minus its own 5pt breathing room).
    private static let nestRadius: CGFloat = Radius.inner(of: Radius.panel, inset: 7)
    /// Version-toggle track and its segments, concentric inside the header row.
    private static let segmentTrackRadius: CGFloat = Radius.control + 1
    private static let segmentRadius: CGFloat = Radius.inner(of: segmentTrackRadius, inset: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().overlay(Palette.mtLine)
            editor
            hint
        }
        .padding(14)
        .frame(width: Self.panelWidth, alignment: .leading)
        // The capsule's glass, one step thicker (mockup 01 lane B `.b-review`).
        .sottoGlass(.panel, in: RoundedRectangle(cornerRadius: Radius.panel))
        // The lens blurs its whole frame; clip it to the card so the corners
        // outside the radius stay untouched desktop (seen on device).
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
        // No painted glow or shadow: the panel window hugs the card, so a blurred
        // halo is cut off at the window edge and reads as a faint square in the
        // corner pockets (measured on device). The material carries its depth.
        .background(sizeReader)
        // Hidden accelerators: ⌘↵ (Return alone inserts a newline in the
        // editor) and — read-only faces only, where no editable text view is
        // around to run `cancelOperation` — Esc.
        .background(
            Group {
                Button("", action: manager.commit)
                    .keyboardShortcut(.return, modifiers: .command)
                if !activeFaceIsEditor {
                    Button("", action: manager.cancel)
                        .keyboardShortcut(.escape, modifiers: [])
                }
                // Comparing ENHANCED against RAW is the panel's core decision;
                // bound only while the toggle is actually on screen, so ⌘1/⌘2
                // never select a version the header does not offer.
                if versionToggleVisible {
                    Button("", action: { manager.selectVersion(.enhanced) })
                        .keyboardShortcut("1", modifiers: .command)
                    Button("", action: { manager.selectVersion(.raw) })
                        .keyboardShortcut("2", modifiers: .command)
                }
            }
            .opacity(0)
            .accessibilityHidden(true)
        )
        .onExitCommand { manager.cancel() }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("REVIEW")
                .foregroundColor(Palette.phosphor)
            if !manager.targetAppName.isEmpty {
                Text("\u{2192}")
                    .foregroundColor(Palette.inkSecondary)
                Text(manager.targetAppName)
                    .foregroundColor(Palette.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if manager.isEnhancing {
                enhancingLabel
            } else if versionToggleVisible {
                versionToggle
            }
        }
        .font(.microlabel(10))
        .tracking(1.1)
        .glassInkShadow()
    }

    private var enhancingLabel: some View {
        Text("ENHANCING\u{2026}")
            .foregroundColor(Palette.inkSecondary)
            .opacity(enhancingPulse ? 0.4 : 1)
            .onAppear {
                // Reduce Motion keeps the label at full ink rather than parking
                // it at the dimmed end of the (now absent) oscillation.
                guard !reduceMotion else { return }
                withAnimation(Motion.pulse(0.8, reduceMotion: reduceMotion)) {
                    enhancingPulse = true
                }
            }
            .onDisappear { enhancingPulse = false }
    }

    /// The version segments are on screen — the ⌘1/⌘2 accelerators and the
    /// hint chip follow it exactly.
    private var versionToggleVisible: Bool {
        !manager.isEnhancing && manager.enhancedText != nil
    }

    private var versionToggle: some View {
        HStack(spacing: 2) {
            // DRAFT exists only when edits/selection deferred the enhanced
            // delivery — the raw-lineage text gets its own segment so RAW
            // stays the pristine as-heard reference. Gone after adoption
            // (draftBase flips to .enhanced).
            if manager.deliveryDeferred && manager.draftBase == .raw {
                segButton("DRAFT", .draft)
            }
            segButton("ENHANCED", .enhanced)
            segButton("RAW", .raw)
        }
        .padding(2)
        // The track is the recess and the selected segment is the lift, so the
        // selection reads without a border around it.
        .sottoGlass(.scrim, in: RoundedRectangle(cornerRadius: Self.segmentTrackRadius,
                                                 style: .continuous))
    }

    /// True when the active face shows the editable draft; false = the face
    /// is a read-only reference (pristine raw, or the enhanced preview over
    /// an edit-deferred draft).
    private var activeFaceIsEditor: Bool {
        switch manager.activeVersion {
        case .draft: return true
        case .enhanced: return manager.draftBase == .enhanced
        case .raw: return false
        }
    }

    private func segButton(_ label: String, _ version: ComposeReviewWindowManager.Version) -> some View {
        let selected = manager.activeVersion == version
        // Chrome sits INSIDE the button label so the press feedback scales the
        // whole segment, not just its text.
        return Button(action: { manager.selectVersion(version) }) {
            Text(label)
                .foregroundColor(selected ? Palette.inkPrimary : Palette.inkSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .glassInkShadow()
                .background(
                    RoundedRectangle(cornerRadius: Self.segmentRadius, style: .continuous)
                        .fill(selected ? Palette.glassChipFill : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableChipStyle())
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if activeFaceIsEditor {
                    MultiSelectTextView(
                        text: $manager.draft,
                        underlineRanges: manager.changedSpans,
                        onSelectionChange: { manager.noteSelection(nonEmpty: $0) },
                        onCommit: manager.commit,
                        onCancel: manager.cancel
                    )
                } else if manager.activeVersion == .raw {
                    readOnlyViewer(manager.rawText)
                } else {
                    readOnlyViewer(manager.enhancedText ?? "")
                }
            }
            .frame(height: editorHeight)
            if let tag = nestTag {
                Text(tag)
                    .font(.microlabel(10))
                    .tracking(1.3)
                    .foregroundColor(Palette.inkSecondary)
            }
        }
        .padding(8)
        // The transcript is the one thing here the user actually reads and it
        // runs to many lines, so it gets a soft recess to settle on. A recess,
        // not a frost: the glass already dims what is behind it.
        .sottoGlass(.scrim, in: RoundedRectangle(cornerRadius: Self.nestRadius, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Measure the rendered text height (matching font + width) and size
        // the editor to it, clamped — so it expands with content.
        .background(textMeasurer)
    }

    /// The inactive-lineage reference face, read-only (pristine raw, or the
    /// enhanced preview over an edit-deferred draft).
    private func readOnlyViewer(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.transcript(15))
                .lineSpacing(3)
                .foregroundColor(Palette.inkPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var nestTag: String? {
        if manager.isEnhancing { return nil }
        switch manager.activeVersion {
        case .draft:
            return nil
        case .raw:
            // Toggle-reachable RAW is always the pristine as-heard reference.
            return manager.enhancedText != nil ? "RAW \u{00B7} AS HEARD" : nil
        case .enhanced:
            guard manager.enhancedText != nil, manager.changeCount > 0 else { return nil }
            return "\(manager.changeCount) \(manager.changeCount == 1 ? "CHANGE" : "CHANGES") FROM RAW"
        }
    }

    /// Invisible copy of the displayed text laid out at the editor's content
    /// width; its height drives `editorHeight`.
    private var textMeasurer: some View {
        let displayed: String
        if activeFaceIsEditor {
            displayed = manager.draft
        } else {
            displayed = manager.activeVersion == .raw ? manager.rawText : (manager.enhancedText ?? "")
        }
        return Text(displayed.isEmpty ? " " : displayed)
            .font(.transcript(15))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: TextHeightKey.self, value: geo.size.height)
                }
            )
            .hidden()
            .onPreferenceChange(TextHeightKey.self) { h in
                let target = min(max(h + Self.editorChrome, Self.minEditorHeight), Self.maxEditorHeight)
                if abs(target - editorHeight) > 0.5 { editorHeight = target }
            }
    }

    private var hint: some View {
        HStack(spacing: 6) {
            hintChip("\u{2318}\u{21A9}", manager.isEnhancing ? "paste raw now" : "paste")
            hintChip("esc", "cancel")
            hintChip("\u{2318}D", "multi-edit")
            if versionToggleVisible {
                hintChip("\u{2318}1/2", "version")
            }
            Spacer(minLength: 0)
        }
        .font(.microlabel(10))
        .tracking(0.9)
    }

    /// Keycap + label pair (mockup 03 `.keycap`) — the same chip recipe as
    /// `MatteCapsuleView.retryChip`, so a key hint reads as a key hint.
    private func hintChip(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).foregroundColor(Palette.phosphor)
            Text(label).foregroundColor(Palette.inkSecondary)
        }
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .sottoGlass(.chip, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private var sizeReader: some View {
        GeometryReader { geo in
            Color.clear.preference(key: ComposeSizeKey.self, value: geo.size)
        }
        .onPreferenceChange(ComposeSizeKey.self) { manager.contentSizeChanged($0) }
    }
}

private struct ComposeSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct TextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
