import SwiftUI
import AppKit

// Cmd+D occurrence search for the review editor. NSString/UTF-16 offsets
// throughout, matching NSTextView's selectedRanges coordinate space.
enum OccurrenceFinder {
    /// Next occurrence of `query` searching forward from `location`, wrapping
    /// to the start, skipping ranges already in `selected`. Case-sensitive,
    /// non-overlapping. Returns nil when every occurrence is already selected.
    static func nextOccurrence(of query: String, in text: String, after location: Int, excluding selected: [NSRange]) -> NSRange? {
        guard !query.isEmpty else { return nil }
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        let start = min(max(location, 0), ns.length)
        let segments = [NSRange(location: start, length: ns.length - start),
                        NSRange(location: 0, length: start)]
        for segment in segments {
            var range = segment
            while range.length > 0 {
                let found = ns.range(of: query, options: [], range: range)
                guard found.location != NSNotFound else { break }
                if !selected.contains(found) { return found }
                let next = found.location + found.length
                let end = segment.location + segment.length
                guard next < end else { break }
                range = NSRange(location: next, length: end - next)
            }
        }
        return nil
    }
}

final class MultiSelectNSTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    // NSTextView renders multiple non-empty selections but neither fans typing
    // out to them nor supports multiple insertion points, so mirrored editing
    // keeps its own caret list: the visible caret is real, the rest are
    // replayed on every insert/backspace. Any other mutation or a selection
    // change ends the session.
    private var mirrorCarets: [Int]?
    private var visibleCaretIndex = 0
    private var primaryLocation: Int?
    private var isProgrammaticSelection = false
    private var isFanningOut = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Panel is rebuilt every present; grab focus on attach (replaces the
        // TextEditor @FocusState wiring).
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers == "d" {
            selectNextOccurrence()
            return true
        }
        if mods == .command, event.keyCode == 36 { // ⌘↩ — commit even though the field is multi-line
            onCommit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if mirrorCarets != nil {
            // VS Code behavior: Esc drops the extra cursors first.
            endMultiEdit()
            return
        }
        let ranges = selectedRanges.map(\.rangeValue)
        if ranges.count > 1 {
            // First Esc collapses multi-selection, second cancels the panel.
            setSelectedRangeProgrammatically(ranges[0])
        } else {
            onCancel?()
        }
    }

    private func selectNextOccurrence() {
        let ranges = selectedRanges.map(\.rangeValue)
        guard let last = ranges.last else { return }
        if ranges.count == 1 && last.length == 0 {
            let word = selectionRange(forProposedRange: last, granularity: .selectByWord)
            if word.length > 0 {
                primaryLocation = word.location
                setSelectedRangeProgrammatically(word)
            }
            return
        }
        guard last.length > 0 else { return }
        if ranges.count == 1 { primaryLocation = last.location }
        let query = (string as NSString).substring(with: last)
        guard let next = OccurrenceFinder.nextOccurrence(
            of: query, in: string, after: last.location + last.length, excluding: ranges
        ) else { return }
        isProgrammaticSelection = true
        setSelectedRanges((ranges + [next]).map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
        isProgrammaticSelection = false
        scrollRangeToVisible(next)
    }

    // MARK: - Mirrored multi-edit

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let typed = (insertString as? String) ?? (insertString as? NSAttributedString)?.string
        guard let typed, replacementRange.location == NSNotFound else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        let ranges = selectedRanges.map(\.rangeValue)
        if ranges.count > 1 {
            beginSession(targets: ranges, replacement: typed)
        } else if let carets = mirrorCarets {
            applyToSession(targets: carets.map { NSRange(location: $0, length: 0) }, replacement: typed)
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        let ranges = selectedRanges.map(\.rangeValue)
        if ranges.count > 1 {
            beginSession(targets: ranges.map(expandedForBackwardDelete), replacement: "")
        } else if let carets = mirrorCarets {
            applyToSession(targets: carets.map { expandedForBackwardDelete(NSRange(location: $0, length: 0)) }, replacement: "")
        } else {
            super.deleteBackward(sender)
        }
    }

    private func expandedForBackwardDelete(_ range: NSRange) -> NSRange {
        guard range.length == 0, range.location > 0 else { return range }
        let prev = (string as NSString).rangeOfComposedCharacterSequence(at: range.location - 1)
        return NSRange(location: prev.location, length: range.location - prev.location)
    }

    private func beginSession(targets: [NSRange], replacement: String) {
        let sorted = targets.sorted { $0.location < $1.location }
        visibleCaretIndex = sorted.firstIndex(where: { $0.location == primaryLocation }) ?? 0
        applyToSession(targets: sorted, replacement: replacement)
    }

    private func applyToSession(targets sorted: [NSRange], replacement: String) {
        guard let carets = fanOut(targets: sorted, replacement: replacement), !carets.isEmpty else { return }
        mirrorCarets = carets
        visibleCaretIndex = min(visibleCaretIndex, carets.count - 1)
        setSelectedRangeProgrammatically(NSRange(location: carets[visibleCaretIndex], length: 0))
        scrollRangeToVisible(selectedRange())
    }

    /// Replaces every target (ascending, non-overlapping) with `replacement`
    /// in one undo group; returns the caret after each replacement.
    private func fanOut(targets sorted: [NSRange], replacement: String) -> [Int]? {
        guard let storage = textStorage,
              shouldChangeText(inRanges: sorted.map { NSValue(range: $0) },
                               replacementStrings: sorted.map { _ in replacement })
        else { return nil }
        let repLen = (replacement as NSString).length
        isFanningOut = true
        defer { isFanningOut = false }
        var carets: [Int] = []
        var shift = 0
        for range in sorted {
            let target = NSRange(location: range.location + shift, length: range.length)
            storage.replaceCharacters(in: target, with: replacement)
            carets.append(target.location + repLen)
            shift += repLen - range.length
        }
        didChangeText()
        highlightMirrorSpans(carets: carets, length: repLen)
        return carets
    }

    private func highlightMirrorSpans(carets: [Int], length: Int) {
        guard length > 0, let layoutManager else { return }
        for caret in carets {
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45),
                forCharacterRange: NSRange(location: caret - length, length: length)
            )
        }
    }

    private func endMultiEdit() {
        mirrorCarets = nil
        primaryLocation = nil
        layoutManager?.removeTemporaryAttribute(
            .backgroundColor,
            forCharacterRange: NSRange(location: 0, length: (string as NSString).length)
        )
    }

    // Any text change we didn't fan out ourselves (paste, undo, IME, drag)
    // invalidates the mirror carets.
    override func didChangeText() {
        if !isFanningOut && mirrorCarets != nil { endMultiEdit() }
        super.didChangeText()
    }

    // Any selection the user makes (click, arrows) ends the session.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        if !isProgrammaticSelection && !isFanningOut && mirrorCarets != nil {
            endMultiEdit()
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    }

    private func setSelectedRangeProgrammatically(_ range: NSRange) {
        isProgrammaticSelection = true
        setSelectedRange(range)
        isProgrammaticSelection = false
    }
}

struct MultiSelectTextView: NSViewRepresentable {
    @Binding var text: String
    /// Changed-word spans (UTF-16, in `text`) drawn with a subtle accent
    /// underline via temporary attributes — glyph-only, never text storage,
    /// so the multi-edit machinery and plain-text pasteboard are untouched.
    var underlineRanges: [NSRange] = []
    /// Reports whether any selected range is non-empty — the review manager
    /// treats an active selection as user intent and defers the enhanced swap.
    var onSelectionChange: ((Bool) -> Void)? = nil
    var onCommit: () -> Void
    var onCancel: () -> Void

    /// New York serif at 15 — spoken words read as writing (Font.transcript);
    /// chrome stays mono.
    private static let transcriptFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 15)
        guard let descriptor = base.fontDescriptor.withDesign(.serif),
              let serif = NSFont(descriptor: descriptor, size: 15) else { return base }
        return serif
    }()

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MultiSelectNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        textView.font = Self.transcriptFont
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: Self.transcriptFont,
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor(Palette.inkPrimary),
        ]
        textView.textColor = NSColor(Palette.inkPrimary)
        textView.insertionPointColor = NSColor(Palette.inkPrimary)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MultiSelectNSTextView else { return }
        context.coordinator.parent = self
        textView.onCommit = onCommit
        textView.onCancel = onCancel
        if textView.string != text {
            // Whole-string swap (enhanced delivery) — the manager defers the
            // swap while a non-empty selection exists, so only a caret can be
            // live here: carry it across, clamped, instead of throwing it back
            // to the document start.
            let caret = textView.selectedRange().location
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(caret, (text as NSString).length), length: 0))
        }
        // Accent is baked into the temporary underline attributes — re-apply
        // when the stored choice changes (the AccentObserving host root
        // re-runs this update on accent change), not just when ranges do.
        let accent = AccentStore.shared.choice
        if context.coordinator.appliedUnderlines != underlineRanges
            || context.coordinator.appliedAccent != accent {
            context.coordinator.appliedUnderlines = underlineRanges
            context.coordinator.appliedAccent = accent
            applyUnderlines(to: textView)
        }
    }

    private func applyUnderlines(to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let length = (textView.string as NSString).length
        let full = NSRange(location: 0, length: length)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: full)
        for range in underlineRanges where NSMaxRange(range) <= length {
            layoutManager.addTemporaryAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                forCharacterRange: range
            )
            layoutManager.addTemporaryAttribute(
                .underlineColor,
                value: NSColor(Palette.phosphor).withAlphaComponent(0.65),
                forCharacterRange: range
            )
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultiSelectTextView
        var appliedUnderlines: [NSRange] = []
        var appliedAccent: AccentChoice = AccentStore.shared.choice
        init(_ parent: MultiSelectTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.onSelectionChange?(textView.selectedRanges.contains { $0.rangeValue.length > 0 })
        }
    }
}
