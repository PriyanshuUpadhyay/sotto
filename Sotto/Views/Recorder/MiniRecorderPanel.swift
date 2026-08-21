import SwiftUI
import AppKit
import os

class MiniRecorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "MiniRecorderPanel")

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Active-Space changes (4-finger swipe into a full-screen app, Mission
        // Control teleport, an app entering full-screen while recording) don't
        // fire `didChangeScreenParameters`, yet the capsule must re-anchor +
        // re-order-front into the new Space — otherwise it strands on the Space
        // it was last shown on (the bug: capsule lands on "Desktop 2" instead of
        // floating over the active full-screen app). NSWorkspace posts this on
        // its OWN notificationCenter, not the default one.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleActiveSpaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func configurePanel() {
        isFloatingPanel = true
        applySpaceBehavior()
        // Constellation is fixed-position (bottom strip). Disable drag.
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
        // Spec §3.1 panel-infrastructure decision — full-strip panel with
        // hit-test passthrough EXCEPT on the satellite frames. Satellites
        // are display-only in v1, so passing the entire panel through is
        // correct and lets menu-bar clicks fall through unimpeded.
        ignoresMouseEvents = true
    }

    /// Dock-safe capsule origin (council change #1, spec §3). The literal
    /// screen-bottom edge is the macOS auto-hide-Dock trigger zone, so the
    /// matte capsule must sit **≥24px above the visible bottom** and never
    /// place a hover/visual target in the bottom ~16px. Pure for testability;
    /// returns the capsule's bottom-edge lift (centred horizontally).
    ///
    /// `visibleBottom` is the gap between the screen's hardware bottom
    /// (`frame.minY`) and the Dock-cleared `visibleFrame.minY`. The mini panel
    /// already anchors its strip at `visibleFrame.minY`; this lift is applied
    /// to the capsule INSIDE that strip via `dockSafeBottomInset`.
    static func dockSafeCapsuleOrigin(screenFrame: NSRect, visibleBottom: CGFloat,
                                      capsuleHeight: CGFloat) -> CGPoint {
        _ = capsuleHeight
        let buffer: CGFloat = 24
        let y = max(visibleBottom + buffer, 16 + buffer)
        return CGPoint(x: screenFrame.midX, y: y)
    }

    /// Bottom inset (above the strip's own `visibleFrame.minY` anchor) for the
    /// capsule inside the full-strip panel. The strip already clears the Dock;
    /// this lifts the capsule the additional Dock-safe `buffer` so nothing
    /// interactive lands in the bottom ~16px even on an empty `visibleFrame`.
    static let dockSafeBottomInset: CGFloat = 24

    static func calculateWindowMetrics() -> NSRect {
        guard let screen = NSScreen.active else {
            return NSRect(x: 0, y: 0, width: 1440, height: ConstellationLayout.panelHeight)
        }

        // Full-strip panel anchored at the BOTTOM of the active screen.
        // Constellation satellites live at fixed positions inside this
        // canvas; the panel is the geometry, not the silhouette.
        // `visibleFrame.minY` (not `frame`) so the strip clears the Dock.
        let width: CGFloat = screen.frame.width
        let height: CGFloat = ConstellationLayout.panelHeight

        return NSRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.minY,
            width: width,
            height: height
        )
    }

    /// Establish the cross-Space floating behavior. macOS silently drops a
    /// `.canJoinAllSpaces` / `.fullScreenAuxiliary` window's full-screen-Space
    /// membership over an accessory (`LSUIElement`) app's lifetime (activation-policy
    /// flips, Space transitions). Crucially, once dropped, re-setting the SAME
    /// `collectionBehavior` on the existing window does NOT restore it — only a
    /// freshly-built window re-registers (which is why a relaunch "fixes" it). So
    /// `MiniWindowManager` rebuilds the panel on every `show()`; this just applies
    /// the behavior to that fresh panel.
    func applySpaceBehavior() {
        // `.popUpMenu` (101) composites above observed full-screen Metal /
        // Stage-Manager modes, unlike `.statusBar + 3` (28) which disappeared
        // under them.
        level = .popUpMenu
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    @objc private func handleScreenParametersChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.setFrame(MiniRecorderPanel.calculateWindowMetrics(), display: true)
        }
    }

    @objc private func handleActiveSpaceChange() {
        // Only re-surface if currently visible — never force the capsule onto a
        // new Space the user swiped to with no active recording.
        guard isVisible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.isVisible else { return }
            self.applySpaceBehavior()
            self.setFrame(MiniRecorderPanel.calculateWindowMetrics(), display: true)
            self.orderFrontRegardless()
        }
    }

    func show() {
        // Re-assert before every show so a stale, single-Space-pinned panel
        // floats over the active (incl. full-screen) Space again.
        applySpaceBehavior()
        let metrics = MiniRecorderPanel.calculateWindowMetrics()
        setFrame(metrics, display: true)
        orderFrontRegardless()
        logger.notice("show – behavior=\(self.collectionBehavior.rawValue, privacy: .public) level=\(self.level.rawValue, privacy: .public) policy=\(NSApp.activationPolicy().rawValue, privacy: .public) frame=\(NSStringFromRect(self.frame), privacy: .public) mainScreen=\(NSStringFromRect(NSScreen.main?.frame ?? .zero), privacy: .public)")
        // TEMP DIAGNOSTIC: is the panel on the currently-active Space, or stranded
        // on a stale full-screen Space? front=frontmost app at show time.
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        logger.notice("show SPACE – isVisible=\(self.isVisible, privacy: .public) isOnActiveSpace=\(self.isOnActiveSpace, privacy: .public) front=\(front, privacy: .public)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.logger.notice("show SPACE +250ms – isOnActiveSpace=\(self.isOnActiveSpace, privacy: .public)")
        }
    }
    
    func hide(completion: @escaping () -> Void) {
        completion()
    }
} 