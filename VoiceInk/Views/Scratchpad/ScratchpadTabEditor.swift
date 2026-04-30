import SwiftUI
import SwiftData
import AppKit

/// W12.E single-tab editor. Wraps `NSTextView` so we can read selectedRange
/// (for dictation-into-place) and drive autosave via `textDidChange`.
/// `TextEditor` doesn't expose either. See plan
/// `docs/superpowers/plans/W12E-scratchpad.md` §Task 6.
struct ScratchpadTabEditor: View {
    @Bindable var document: ScratchpadDocument
    @ObservedObject var store: ScratchpadStore

    @State private var showHistory = false
    @State private var savedAgoTick = Date()

    private let footerTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ScratchpadTextView(document: document, store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .onReceive(footerTimer) { _ in
            savedAgoTick = Date()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(savedAgoString)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Button("History") { showHistory = true }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(document.versions.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .sheet(isPresented: $showHistory) {
            ScratchpadVersionHistorySheet(document: document, store: store)
        }
    }

    private var savedAgoString: String {
        // Reference `savedAgoTick` so SwiftUI re-renders this view every
        // 5s — keeps the relative timestamp fresh without polling.
        _ = savedAgoTick
        let delta = Date().timeIntervalSince(document.updatedAt)
        if delta < 2 { return "Saved" }
        if delta < 60 { return "Saved \(Int(delta))s ago" }
        let minutes = Int(delta / 60)
        return "Saved \(minutes)m ago"
    }
}

private struct ScratchpadTextView: NSViewRepresentable {
    @Bindable var document: ScratchpadDocument
    @ObservedObject var store: ScratchpadStore

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.string = document.content
        // Plain-text only per Migration policy #15. Strip incoming RTF on paste.
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Reflect external changes (e.g., restoreVersion) without breaking
        // the user's in-flight selection.
        if textView.string != document.content {
            let range = textView.selectedRange()
            textView.string = document.content
            // Clamp the prior selection to the new text length.
            let clamped = NSRange(
                location: min(range.location, document.content.utf16.count),
                length: 0
            )
            textView.setSelectedRange(clamped)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: ScratchpadTextView
        weak var textView: NSTextView?

        init(_ parent: ScratchpadTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.store.updateContent(parent.document, content: textView.string)
        }
    }
}
