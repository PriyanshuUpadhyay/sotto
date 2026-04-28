import Cocoa
import SwiftUI
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var menuBarManager: MenuBarManager?

    /// Engine-state → menu bar icon bridge. Lifetime tracks the app process
    /// (AppDelegate is retained for the duration). Bound to the engine in
    /// `VoiceInkApp.init` after the engine finishes constructing.
    let recordingStateObserver = RecordingStateObserver()

    /// Help → Show Tutorial window (P2.G). Held weakly via a strong reference
    /// here + `isReleasedWhenClosed = false` so re-invoking the menu item
    /// focuses the existing window rather than spawning duplicates. Cleared
    /// in `windowWillClose` when the user closes it.
    private var tutorialWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager?.applyActivationPolicy()
        installHelpMenuItems()
    }

    // MARK: - Help → Show Tutorial (P2.G)

    /// Appends "Show Tutorial" to the system Help menu. Idempotent — safe to
    /// call once at launch; guards against double-install on hot reload.
    private func installHelpMenuItems() {
        guard let helpMenu = NSApp.mainMenu?.item(withTitle: "Help")?.submenu else { return }
        let selector = #selector(showTutorialFromHelp(_:))
        if helpMenu.items.contains(where: { $0.action == selector }) { return }
        helpMenu.addItem(.separator())
        let item = NSMenuItem(title: "Show Tutorial", action: selector, keyEquivalent: "")
        item.target = self
        helpMenu.addItem(item)
    }

    @objc private func showTutorialFromHelp(_ sender: Any?) {
        if let existing = tutorialWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingView(rootView: TutorialReplayHost(onClose: { [weak self] in
            self?.tutorialWindow?.close()
        }))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceInk Tutorial"
        window.contentView = host
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        tutorialWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow, w === tutorialWindow {
            tutorialWindow = nil
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let menuBarManager = menuBarManager, !menuBarManager.isMenuBarOnly {
            if WindowManager.shared.showMainWindow() != nil {
                return false
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // Stash URL when app cold-starts to avoid spawning a new window/tab
    var pendingOpenFileURL: URL?
    
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { SupportedMedia.isSupported(url: $0) }) else {
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)

        if WindowManager.shared.currentMainWindow() == nil {
            // Cold start: do NOT create a window here to avoid extra window/tab.
            // Defer to SwiftUI’s WindowGroup-created ContentView and let it process this later.
            pendingOpenFileURL = url
        } else {
            // Running: focus current window and route in-place to Transcribe Audio
            menuBarManager?.focusMainWindow()
            NotificationCenter.default.post(name: .navigateToDestination, object: nil, userInfo: ["destination": "Transcribe Audio"])
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openFileForTranscription, object: nil, userInfo: ["url": url])
            }
        }
    }
}

// MARK: - TutorialReplayHost (P2.G)
//
// Hosts the cinematic walkthrough inside the Help → Show Tutorial window.
// Backdrop matches the cinematic's onyx environment so the embedded glass
// card reads correctly. `onFinish` triggers `onClose`, dismissing the window
// after one play — re-invoke from Help to watch again.

private struct TutorialReplayHost: View {
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea()
            CinematicWalkthrough(onFinish: onClose)
        }
        .frame(minWidth: 900, minHeight: 560)
    }
}
