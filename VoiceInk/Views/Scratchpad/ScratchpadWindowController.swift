import SwiftUI
import SwiftData
import AppKit

/// W12.E summoned-window controller. Mirrors `HistoryWindowController` shape;
/// adds `appendAsNewTab(text:)` and `insertIntoActiveTab(_:)` for paste-
/// fallback and dictation-into-place. See plan
/// `docs/superpowers/plans/W12E-scratchpad.md` §Task 4 + §Migration policy #9.
@MainActor
final class ScratchpadWindowController: NSObject, NSWindowDelegate {
    static let shared = ScratchpadWindowController()

    private var window: ScratchpadWindow?
    private var store: ScratchpadStore?
    private let identifier = NSUserInterfaceItemIdentifier("com.prakashjoshipax.voiceink.scratchpadWindow")
    private let autosaveName = NSWindow.FrameAutosaveName("VoiceInkScratchpadWindowFrame")

    private override init() { super.init() }

    /// Returns true when the Scratchpad is the key window AND a tab editor
    /// is the first responder — the dictation-into-place gate.
    var isFocusedAndKey: Bool {
        guard let window, window.isKeyWindow else { return false }
        // First-responder is a chain — accept any descendant of the contentView.
        return window.firstResponder is NSTextView
    }

    func toggle(modelContainer: ModelContainer) {
        if window == nil {
            show(modelContainer: modelContainer)
        } else if window?.isKeyWindow == true {
            window?.orderOut(nil)
        } else {
            window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func show(modelContainer: ModelContainer) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        let store = ScratchpadStore(modelContext: modelContainer.mainContext)
        self.store = store
        window = createScratchpadWindow(store: store, modelContainer: modelContainer)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Paste-fallback hook — append the rescued text as a new tab. Does NOT
    /// open the window (the user finds it via ⌥+S; opening unprompted would
    /// steal focus from whatever they're currently doing). Lazily constructs
    /// a store if the user hasn't opened the Scratchpad yet this session.
    func appendAsNewTab(text: String, modelContainer: ModelContainer) {
        if store == nil {
            store = ScratchpadStore(modelContext: modelContainer.mainContext)
        }
        store?.appendFallbackTab(text: text)
    }

    /// Dictation-into-place hook — insert at the active editor's cursor.
    /// Replaces the selected range if length > 0; otherwise inserts at caret.
    /// Cursor advances to end of inserted text (NSTextView default behavior).
    func insertIntoActiveTab(_ text: String) {
        guard let textView = window?.firstResponder as? NSTextView else { return }
        let range = textView.selectedRange()
        if textView.shouldChangeText(in: range, replacementString: text) {
            textView.replaceCharacters(in: range, with: text)
            textView.didChangeText()
        }
    }

    // MARK: - Window construction

    private func createScratchpadWindow(store: ScratchpadStore,
                                         modelContainer: ModelContainer) -> ScratchpadWindow {
        let view = ScratchpadView(store: store)
            .modelContainer(modelContainer)
            .frame(minWidth: 600, minHeight: 400)

        let host = NSHostingController(rootView: view)

        let win = ScratchpadWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.contentViewController = host
        win.title = "Sotto — Scratchpad"
        win.identifier = identifier
        win.delegate = self
        // Mirror `WindowManager.configureWindow` glass flags so the SwiftUI
        // root's `.adaptiveGlassBackground()` reveals wallpaper through the
        // NSWindow. Spec §6.1 / W8.
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.backgroundColor = .clear
        win.isReleasedWhenClosed = false
        win.isOpaque = false
        win.collectionBehavior = [.fullScreenPrimary]
        win.minSize = NSSize(width: 600, height: 400)
        win.setFrameAutosaveName(autosaveName)
        if !win.setFrameUsingName(autosaveName) {
            win.center()
        }
        return win
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow,
              win.identifier == identifier else { return }
        // Capture the active tab on close (Migration policy #6) + flush any
        // in-flight 800ms autosave debounces so close isn't lossy.
        if let store, let activeId = store.activeTabId,
           let active = store.documents.first(where: { $0.id == activeId }) {
            store.captureVersion(active, force: true)
        }
        let storeRef = store
        Task {
            await storeRef?.flushAll()
        }
        window = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let win = notification.object as? NSWindow,
              win.identifier == identifier else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
