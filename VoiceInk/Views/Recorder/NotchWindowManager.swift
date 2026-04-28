import SwiftUI
import AppKit

@MainActor
class NotchWindowManager: ObservableObject {
    @Published var isVisible = false
    private var windowController: NSWindowController?
    private var panel: NotchRecorderPanel?

    private let makeView: (NotchWindowManager) -> AnyView
    private let enhancementService: AIEnhancementService

    init(engine: VoiceInkEngine, recorder: Recorder, failureRegistry: FailureRegistry) {
        guard let enhancementService = engine.enhancementService,
              let aiService = enhancementService.getAIService() else {
            preconditionFailure("VoiceInkEngine.enhancementService and AIService must be non-nil when creating NotchWindowManager")
        }
        self.enhancementService = enhancementService
        self.makeView = { manager in
            AnyView(
                HaloRecorderView(
                    stateProvider: engine,
                    recorder: recorder,
                    aiService: aiService,
                    windowManager: manager,
                    isVisible: { manager.isVisible },
                    // Notch panel always uses notch silhouette — its frame already
                    // accounts for the physical notch area at the top.
                    mode: .notch
                )
                .environmentObject(manager)
                .environmentObject(enhancementService)
                .environmentObject(failureRegistry)
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHideNotification),
            name: NSNotification.Name("HideNotchRecorder"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleHideNotification() {
        hide()
    }

    func show() {
        if isVisible { return }
        if panel == nil { initializeWindow() }
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
        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        let newPanel = NotchRecorderPanel(contentRect: metrics.frame)
        let view = makeView(self)
        let hostingController = NotchRecorderHostingController(rootView: view)
        newPanel.contentView = hostingController.view
        panel = newPanel
        windowController = NSWindowController(window: newPanel)
        newPanel.orderFrontRegardless()
    }

    private func deinitializeWindow() {
        panel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        panel = nil
    }

    func toggle() {
        isVisible ? hide() : show()
    }
}
