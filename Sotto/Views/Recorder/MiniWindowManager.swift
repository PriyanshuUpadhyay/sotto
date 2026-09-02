import SwiftUI
import AppKit

@MainActor
class MiniWindowManager: ObservableObject {
    @Published var isVisible = false
    private var windowController: NSWindowController?
    private var panel: MiniRecorderPanel?
    /// Built once and re-parented into every rebuilt panel: the panel has to be
    /// fresh (see `show()`), the SwiftUI graph does not, and rebuilding it sat
    /// synchronously between the hotkey and the capsule's first frame.
    private var hostingController: NSHostingController<AnyView>?

    private let makeView: (MiniWindowManager) -> AnyView

    init(engine: SottoEngine, recorder: Recorder, failureRegistry: FailureRegistry) {
        guard let enhancementService = engine.enhancementService,
              let aiService = enhancementService.getAIService() else {
            preconditionFailure("SottoEngine.enhancementService and AIService must be non-nil when creating MiniWindowManager")
        }
        self.makeView = { manager in
            // AccentObserving: this panel is its own NSHostingController root,
            // outside the observed window roots — accent changes must
            // invalidate it here.
            AnyView(
                AccentObserving {
                    HaloRecorderView(
                        stateProvider: engine,
                        recorder: recorder,
                        aiService: aiService,
                        windowManager: manager,
                        isVisible: { manager.isVisible },
                        mode: .floating
                    )
                    .environmentObject(manager)
                    .environmentObject(enhancementService)
                    .environmentObject(failureRegistry)
                    // The post-paste ReviewTray is now its OWN independent floating
                    // panel (`ReviewTrayWindowManager`), not an overlay in this strip.
                }
            )
        }
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHideNotification),
            name: NSNotification.Name("HideMiniRecorder"),
            object: nil
        )
    }

    @objc private func handleHideNotification() {
        hide()
    }

    func show() {
        if isVisible { return }
        // Rebuild the panel every show. A REUSED panel silently loses its
        // cross-Space / full-screen-auxiliary membership over the app's
        // lifetime, after which re-asserting the same `collectionBehavior` does
        // NOT restore it (verified: `isOnActiveSpace=false` persists over a
        // full-screen app even with behavior re-set) and the capsule strands on
        // a stale Space. A fresh panel re-registers correctly — which is exactly
        // why a relaunch "fixes" it. Rebuilding here makes every show a relaunch.
        initializeWindow()
        isVisible = true
        panel?.show()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        panel?.orderOut(nil)
    }

    func destroyWindow() {
        isVisible = false
        deinitializeWindow()
    }

    private func initializeWindow() {
        deinitializeWindow()
        let metrics = MiniRecorderPanel.calculateWindowMetrics()
        let newPanel = MiniRecorderPanel(contentRect: metrics)
        let controller = hostingController ?? NSHostingController(rootView: makeView(self))
        hostingController = controller
        newPanel.contentView = controller.view
        panel = newPanel
        windowController = NSWindowController(window: newPanel)
        newPanel.orderFrontRegardless()
    }

    private func deinitializeWindow() {
        panel?.orderOut(nil)
        // A view has one superview, so the hosting view must leave the outgoing
        // panel before the next one adopts it. `hostingController` deliberately
        // survives — it is the view tree the next panel reuses.
        hostingController?.view.removeFromSuperview()
        panel?.contentView = nil
        windowController?.close()
        windowController = nil
        panel = nil
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func setIgnoresMouseEvents(_ ignores: Bool) {
        panel?.ignoresMouseEvents = ignores
    }
}
