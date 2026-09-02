import SwiftUI
import AppKit

/// Floating non-activating toast panel for transient reminders — the
/// onboarding hotkey reminder and the menu-bar confirmation toast. Anchored
/// top-center; auto-dismissed by its caller.
final class AnnouncementManager {
    static let shared = AnnouncementManager()

    private var reminderPanel: NSPanel?

    private init() {}

    @MainActor
    func showReminderToast<Content: View>(_ content: Content, reduceMotion: Bool) {
        dismissReminderToast()

        // AccentObserving: independent NSHostingController root — see MiniWindowManager.
        let hosting = NSHostingController(rootView: AccentObserving { content })
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting.view
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        positionReminder(panel)
        let restFrame = panel.frame
        panel.alphaValue = 0
        if !reduceMotion {
            panel.setFrameOrigin(NSPoint(x: restFrame.minX, y: restFrame.minY + 8))
        }
        panel.makeKeyAndOrderFront(nil as Any?)
        reminderPanel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : MotionTokens.stateEnterDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrame(restFrame, display: true)
            }
        }
    }

    @MainActor
    func dismissReminderToast() {
        guard let panel = reminderPanel else { return }
        reminderPanel = nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0 : MotionTokens.stateExitDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.close()
        })
    }

    @MainActor
    private func positionReminder(_ panel: NSPanel) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        // visibleFrame excludes the menu bar and the notch region — `frame`
        // drew the toast over both. Matches `NotificationManager.positionWindow`.
        let frame = screen.visibleFrame
        let x = frame.midX - (panel.frame.width / 2)
        let y = frame.maxY - 16 - panel.frame.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}


