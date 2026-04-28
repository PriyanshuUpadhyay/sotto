import SwiftUI
import AppKit

class MiniRecorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }
    
    private func configurePanel() {
        isFloatingPanel = true
        // Match the notch recorder so the constellation always sits above app windows.
        level = .statusBar + 3
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Constellation is fixed-position (top strip). Disable drag.
        isMovable = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        // Halo glows are rendered inside the SwiftUI hierarchy via shadow modifiers;
        // a window-level shadow would compete with them.
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        appearance = NSAppearance(named: .darkAqua)
        // Spec §3.1 panel-infrastructure decision — full-strip panel with
        // hit-test passthrough EXCEPT on the satellite frames. Satellites
        // are display-only in v1, so passing the entire panel through is
        // correct and lets menu-bar clicks fall through unimpeded.
        ignoresMouseEvents = true
    }

    static func calculateWindowMetrics() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 1440, height: 120)
        }

        // Spec §3.1 panel-infrastructure decision — full-strip panel
        // anchored at top of the active screen. Constellation satellites
        // (orb / chip / card) live at fixed positions inside this canvas;
        // the panel is the geometry, not the silhouette.
        //
        // `screen.frame` (not `visibleFrame`) so the panel covers the
        // physical notch row — the orb / chip flank the notch at
        // ~26% / ~74% on notched displays, which is inside the
        // notch-baseline strip excluded from `visibleFrame`.
        let width: CGFloat = screen.frame.width
        let height: CGFloat = 120

        return NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    func show() {
        let metrics = MiniRecorderPanel.calculateWindowMetrics()
        setFrame(metrics, display: true)
        orderFrontRegardless()
    }
    
    func hide(completion: @escaping () -> Void) {
        completion()
    }
} 