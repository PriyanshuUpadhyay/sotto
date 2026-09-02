import SwiftUI
import SwiftData
import AppKit
import Combine
import QuartzCore
import os

// MARK: - ReviewTrayPanel
//
// The post-paste ping is its OWN independent floating panel (not an overlay
// inside the bottom recorder strip), fixed at the default anchor above the
// capsule strip — ephemeral, never dragged.
//
// Key-capable so the panel can handle its own ESC and button clicks, but
// `.nonactivatingPanel` keeps the user's frontmost app active: merely SHOWING
// the ping never steals focus, and even clicking it only makes the PANEL key
// (the app underneath stays active). `level = .popUpMenu` + `.fullScreenAuxiliary`
// composite it above full-screen apps like the capsule.
final class ReviewTrayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        applySpaceBehavior()
        isMovable = false
        backgroundColor = .clear
        isOpaque = false
        // No system shadow: a Liquid Glass lens reports a rectangular alpha to
        // the window shadow, which then paints a square behind the rounded
        // surface (seen on device). The SwiftUI content draws its own depth.
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        animationBehavior = .none
    }

    /// Establish the cross-Space floating behavior. macOS silently drops a
    /// `.canJoinAllSpaces` window's full-screen-Space membership over an accessory
    /// app's lifetime (activation-policy flips, Space transitions), and re-setting
    /// the SAME `collectionBehavior` does NOT restore it — only a freshly-built
    /// window re-registers. So the manager rebuilds the panel on every present;
    /// this just applies the behavior to that fresh panel.
    func applySpaceBehavior() {
        level = .popUpMenu
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}

// MARK: - ReviewTrayWindowManager
//
// Owns the `ReviewTrayPanel`, drives show/dismiss, hosts the `ReviewTray` ping
// pill, and runs its lifecycle: fade in on paste, hold ~1.5s, fade out — with
// hover (or the panel becoming key) pausing the auto-dismiss. Explicit dismiss
// triggers stay: click-outside, ESC (routed via `MiniRecorderShortcutManager`,
// which reads `isPresented` / `isPanelKey`), pill actions, and a superseding
// recording.
@MainActor
final class ReviewTrayWindowManager: NSObject, ObservableObject {
    private static let defaultSize = CGSize(width: 240, height: 38)
    /// Lift above the screen's visible bottom: clears the Dock-safe inset (24)
    /// + the capsule height (38) + a small gap, so the ping sits just ABOVE the
    /// capsule pill.
    private static let capsuleClearance: CGFloat = 78

    @Published private(set) var currentEvent: PasteEvent?
    @Published private(set) var isPresented = false
    /// True only while the user has clicked into the panel (buttons), at which
    /// point ESC is handled locally by the panel, not the global hook.
    @Published private(set) var isPanelKey = false

    private var panel: ReviewTrayPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var modelContext: ModelContext?

    private var cancellables = Set<AnyCancellable>()
    private var clickMonitorGlobal: Any?
    private var clickMonitorLocal: Any?
    private var autoDismissTask: Task<Void, Never>?
    private var isHovering = false
    /// Invalidates a stale fade-out completion — bumped on every present, on
    /// dismiss, and when the user re-engages (hover/key) mid-fade.
    private var fadeToken = 0
    /// Hold budget left before the fade-out. Pausing (hover/key) banks the
    /// remainder; resuming spends it — never a fresh full hold.
    private var holdRemaining: Double = 0
    private var holdStartedAt: CFTimeInterval?
    private var lastContentSize: CGSize = defaultSize

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "ReviewTray")

    func configure(engine: SottoEngine, modelContext: ModelContext) {
        self.modelContext = modelContext
        // A superseding recording tears the ping down instantly so the next
        // dictation starts with no lingering panel.
        engine.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state == .recording || state == .starting { self?.dismiss() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Present / dismiss

    func present(_ event: PasteEvent) {
        guard let modelContext else { return }
        // Rebuild the panel every present. A reused panel silently loses its
        // cross-Space / full-screen-auxiliary membership over the app's lifetime,
        // after which re-asserting the same `collectionBehavior` does NOT restore
        // it and the ping strands on a stale Space. A fresh panel re-registers
        // correctly — which is why a relaunch "fixes" it.
        rebuildPanel(modelContext: modelContext)
        currentEvent = event
        isHovering = false
        // Orphan any fade still in flight from the PREVIOUS ping so its
        // completion can't dismiss this one.
        fadeToken += 1
        isPresented = true
        positionPanel()
        // Appear WITHOUT becoming key — the user keeps typing in their app.
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        fade(to: 1, duration: MotionTokens.stateEnterDuration, curve: .easeOut)
        installClickMonitors()
        holdRemaining = MotionTokens.trayHold
        scheduleAutoDismiss()
        logger.notice("present – app=\(event.appName, privacy: .public)")
    }

    func dismiss() {
        guard isPresented || currentEvent != nil else { return }
        isPresented = false
        currentEvent = nil
        isHovering = false
        autoDismissTask?.cancel(); autoDismissTask = nil
        fadeToken += 1
        removeClickMonitors()
        panel?.orderOut(nil)
        // Drop the process-lifetime stash (incl. any captured prior clipboard).
        // Ping actions read it synchronously BEFORE calling dismiss().
        CursorPaster.lastPasteContext = nil
    }

    // MARK: - Auto-dismiss (hold → fade), paused on hover / panel key

    func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
        updateAutoDismiss()
    }

    private func updateAutoDismiss() {
        guard isPresented else { return }
        if isHovering || isPanelKey {
            pauseAutoDismiss()
        } else {
            scheduleAutoDismiss()
        }
    }

    /// Pause banks the unspent hold so resuming grants only the REMAINDER,
    /// not a fresh full hold. Also rescues the ping mid-fade.
    private func pauseAutoDismiss() {
        if let started = holdStartedAt {
            holdRemaining = max(0, holdRemaining - (CACurrentMediaTime() - started))
            holdStartedAt = nil
        }
        autoDismissTask?.cancel(); autoDismissTask = nil
        fadeToken += 1
        panel?.alphaValue = 1
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        holdStartedAt = CACurrentMediaTime()
        let remaining = holdRemaining
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.beginFadeOut()
        }
    }

    private func beginFadeOut() {
        guard isPresented else { return }
        fadeToken += 1
        let token = fadeToken
        fade(to: 0, duration: MotionTokens.stateExitDuration, curve: .easeIn) { [weak self] in
            guard let self, self.fadeToken == token else { return }
            self.dismiss()
        }
    }

    /// Panel alpha fade — opacity-only, so it stays under Reduce Motion (the
    /// mockup's convention: fades survive, movement doesn't). `curve` mirrors
    /// the matching MotionTokens easing (ease-out enter / ease-in exit).
    private func fade(
        to alpha: CGFloat,
        duration: Double,
        curve: CAMediaTimingFunctionName,
        completion: (@MainActor () -> Void)? = nil
    ) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: curve)
            panel.animator().alphaValue = alpha
        }, completionHandler: {
            if let completion { Task { @MainActor in completion() } }
        })
    }

    // MARK: - Panel construction + positioning

    private func rebuildPanel(modelContext: ModelContext) {
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        let frame = NSRect(origin: .zero, size: lastContentSize)
        let newPanel = ReviewTrayPanel(contentRect: frame)
        newPanel.delegate = self
        // AccentObserving: independent NSHostingController root — see MiniWindowManager.
        let root = AnyView(
            AccentObserving { ReviewTray(manager: self, modelContext: modelContext) }
        )
        let controller = NSHostingController(rootView: root)
        controller.view.frame = NSRect(origin: .zero, size: frame.size)
        controller.view.autoresizingMask = [.width, .height]
        newPanel.contentView = controller.view
        panel = newPanel
        hostingController = controller
    }

    /// Fixed anchor: bottom-centre, lifted ABOVE the capsule strip.
    private func positionPanel() {
        guard let panel else { return }
        let size = lastContentSize
        let visible = (NSScreen.active ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.minY + Self.capsuleClearance,
            width: size.width, height: size.height
        )
        panel.setFrame(frame, display: false)
    }

    /// SwiftUI reports the pill's full (expanded) fitting size; resize the panel
    /// keeping it bottom-centred. The hover reveal is a mask inside this fixed
    /// frame, so this only fires on content changes (app-name length), never on
    /// hover.
    func contentSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        lastContentSize = size
        guard let panel, isPresented else { return }
        let current = panel.frame
        guard abs(size.width - current.width) > 0.5 || abs(size.height - current.height) > 0.5 else { return }
        let newFrame = NSRect(x: current.midX - size.width / 2, y: current.minY,
                              width: size.width, height: size.height)
        panel.setFrame(newFrame, display: true)
    }

    // MARK: - Click-outside dismiss

    private func installClickMonitors() {
        removeClickMonitors()
        clickMonitorGlobal = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleOutsideClick() }
        }
        clickMonitorLocal = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.handleLocalClick(event) }
            return event
        }
    }

    private func removeClickMonitors() {
        if let m = clickMonitorGlobal { NSEvent.removeMonitor(m); clickMonitorGlobal = nil }
        if let m = clickMonitorLocal { NSEvent.removeMonitor(m); clickMonitorLocal = nil }
    }

    /// A click in any OTHER app is, by definition, outside the ping.
    private func handleOutsideClick() {
        guard isPresented else { return }
        if let panel, panel.frame.contains(NSEvent.mouseLocation) { return }
        dismiss()
    }

    /// A click in one of OUR windows dismisses unless it landed on the ping.
    private func handleLocalClick(_ event: NSEvent) {
        guard isPresented else { return }
        if event.window === panel { return }
        dismiss()
    }
}

// MARK: - NSWindowDelegate (panel-key tracking for ESC layering + dismiss pause)
extension ReviewTrayWindowManager: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        isPanelKey = true
        updateAutoDismiss()
    }
    func windowDidResignKey(_ notification: Notification) {
        isPanelKey = false
        updateAutoDismiss()
    }
}
