import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    private init() {}

    func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // AccentObserving: independent NSHostingController root — see MiniWindowManager.
        let host = NSHostingController(
            rootView: AccentObserving {
                OnboardingFlow(onFinish: { [weak self] in
                    self?.finish()
                })
            }
        )
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: 480, height: 640))
        panel.center()

        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        window?.orderOut(nil)
        window = nil

        // Open the Sotto window now that onboarding is done, via the canonical
        // on-demand coordinator path (the window is no longer auto-created).
        SottoWindowCoordinator.shared.open(tab: .history)

        guard OnboardingState.shared.shouldPresentHotkeyReminder else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            HotkeyReminderToast.show()
        }
    }
}
