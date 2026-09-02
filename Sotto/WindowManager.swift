import SwiftUI
import AppKit
import OSLog

class WindowManager: NSObject {
    static let shared = WindowManager()

    private static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("com.sotto.Sotto.mainWindow")
    private static let mainWindowAutosaveName = NSWindow.FrameAutosaveName("SottoMainWindowFrame")

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "WindowManager")
    private var didApplyInitialPlacement = false

    private override init() {
        super.init()
    }
    
    func configureWindow(_ window: NSWindow) {
        if let existingWindow = NSApplication.shared.windows.first(where: { $0.identifier == Self.mainWindowIdentifier && $0 != window }) {
            logger.notice("configureWindow: duplicate detected, reusing existing window")
            window.close()
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        logger.notice("configureWindow: registering main window")
        
        let requiredStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // W8 — adaptive glass app-wide. Non-opaque + clear bg so the SwiftUI
        // root's `.adaptiveGlassBackground()` (NSVisualEffectView .behindWindow)
        // can reveal wallpaper through the gap behind cards. Spec §1 / §6.1 /
        // docs/superpowers/plans/W8-adaptive-glass-app-wide.md.
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.title = "Sotto"
        window.collectionBehavior = [.fullScreenPrimary]
        window.level = .normal
        window.isOpaque = false
        window.isMovableByWindowBackground = false
        // configureWindow runs after `.windowResizability(.contentSize)` has
        // derived a floor, so a zero size let the user collapse the window until
        // the search field, list and selection bar overlapped — and the size is
        // persisted by setFrameAutosaveName.
        window.minSize = NSSize(width: 720, height: 480)
        window.setFrameAutosaveName(Self.mainWindowAutosaveName)
        applyInitialPlacementIfNeeded(to: window)
        registerMainWindowIfNeeded(window)
        // The Sotto window is opened on demand (via SottoWindowCoordinator /
        // openWindow), so configureWindow only runs once the user has already
        // requested it — bring it to the front.
        window.orderFrontRegardless()
    }

    func registerMainWindow(_ window: NSWindow) {
        window.identifier = Self.mainWindowIdentifier
        window.delegate = self
    }

    private func registerMainWindowIfNeeded(_ window: NSWindow) {
        // Only register the primary content window, identified by the hidden title bar style
        if window.identifier == nil || window.identifier != Self.mainWindowIdentifier {
            registerMainWindow(window)
        }
    }
    
    private func applyInitialPlacementIfNeeded(to window: NSWindow) {
        guard !didApplyInitialPlacement else { return }
        // Attempt to restore previous frame if one exists; otherwise fall back to a centered placement
        if !window.setFrameUsingName(Self.mainWindowAutosaveName) {
            window.center()
        }
        didApplyInitialPlacement = true
    }
}

extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.identifier == Self.mainWindowIdentifier {
            logger.notice("windowWillClose: Sotto window closing")
            window.orderOut(nil)
            didApplyInitialPlacement = false
        }
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == Self.mainWindowIdentifier else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
} 
