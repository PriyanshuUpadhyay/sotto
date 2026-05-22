import SwiftUI
import AppKit

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class NotchRecorderPanel: KeyablePanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        let metrics = NotchRecorderPanel.calculateWindowMetrics()

        super.init(
            contentRect: metrics.frame,
            // No .hudWindow — that imposes macOS's built-in dark HUD blur over the
            // entire panel area, swallowing the Halo pill in a massive dark
            // rectangle. The Halo provides its own material via HaloMaterial, so
            // the panel itself stays transparent and only the pill renders.
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        // `.statusBar + 3` (28) sat below the window level used by some
        // Metal-presented and stage-manager-style full-screen apps, so the
        // panel disappeared in those Spaces. `.popUpMenu` (101) reliably
        // composites above all observed full-screen modes while staying
        // below screensaver / system-modal levels.
        self.level = .popUpMenu
        self.backgroundColor = .clear
        self.isOpaque = false
        self.alphaValue = 1.0
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.appearance = NSAppearance(named: .darkAqua)
        self.styleMask.remove(.titled)
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.isMovable = false
        // Spec §3.1 panel-infrastructure decision: full-strip panel with
        // hit-test passthrough EXCEPT on the satellite frames. Satellites
        // are display-only in v1 (no buttons / popovers — those moved out
        // of the recorder per plan §P1.G), so passing the entire panel
        // through is correct and simple. Menu-bar clicks fall through this
        // strip even though `level = .statusBar + 3` puts the panel
        // visually above the menu bar.
        self.ignoresMouseEvents = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Active-Space changes (4-finger swipe between full-screen apps,
        // Mission Control teleport, app entering full-screen while recording)
        // don't fire `didChangeScreenParameters` even though the panel needs
        // to re-anchor + re-orderFront into the new Space. NSWorkspace fires
        // this notification on its own notificationCenter, NOT the default one.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleActiveSpaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    static func calculateWindowMetrics() -> (frame: NSRect, notchWidth: CGFloat, notchHeight: CGFloat) {
        guard let screen = NSScreen.main else {
            return (NSRect(x: 0, y: 0, width: 1440, height: 120), 280, 24)
        }

        let safeAreaInsets = screen.safeAreaInsets
        let notchHeight: CGFloat = safeAreaInsets.top > 0 ? safeAreaInsets.top : NSStatusBar.system.thickness

        let notchWidth: CGFloat = {
            if let left = screen.auxiliaryTopLeftArea?.width,
               let right = screen.auxiliaryTopRightArea?.width {
                return screen.frame.width - left - right
            }
            return 240
        }()

        // Spec §3.1 panel-infrastructure decision — full-strip panel
        // anchored at top of the active screen. Was content-clamped (the
        // v1 single-pill layout); the constellation pieces sit at fixed
        // x-offsets so the panel becomes the canvas, not the silhouette.
        let totalWidth = screen.frame.width
        let panelHeight: CGFloat = 120
        let xPosition = screen.frame.minX
        let yPosition = screen.frame.maxY - panelHeight

        let frame = NSRect(x: xPosition, y: yPosition, width: totalWidth, height: panelHeight)
        return (frame, notchWidth, notchHeight)
    }

    func show() {
        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        setFrame(metrics.frame, display: true)
        orderFrontRegardless()
    }

    func hide(completion: @escaping () -> Void) {
        completion()
    }

    @objc private func handleScreenParametersChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            let metrics = NotchRecorderPanel.calculateWindowMetrics()
            self.setFrame(metrics.frame, display: true)
        }
    }

    @objc private func handleActiveSpaceChange() {
        // Only re-show if currently visible. We don't want to surface the
        // panel onto a new Space if the user explicitly hid it.
        guard self.isVisible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.isVisible else { return }
            let metrics = NotchRecorderPanel.calculateWindowMetrics()
            self.setFrame(metrics.frame, display: true)
            self.orderFrontRegardless()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

class NotchRecorderHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
