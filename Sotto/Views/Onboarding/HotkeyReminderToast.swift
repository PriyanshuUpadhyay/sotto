import AppKit
import SwiftUI
import KeyboardShortcuts

extension Notification.Name {
    static let firstInvocationDidFire = Notification.Name("firstInvocationDidFire_v1")
}

@MainActor
enum HotkeyReminderToast {
    private static var observer: NSObjectProtocol?

    static func show() {
        let state = OnboardingState.shared
        guard state.shouldPresentHotkeyReminder else { return }
        state.markHotkeyReminderShown()

        let shortcut = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)?.description ?? "⌥ SPACE"
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        AnnouncementManager.shared.showReminderToast(
            HotkeyReminderToastView(shortcut: shortcut, onClose: { dismiss() }),
            reduceMotion: reduceMotion
        )

        observer = NotificationCenter.default.addObserver(
            forName: .firstInvocationDidFire,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in dismiss() }
        }
    }

    static func dismiss() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        AnnouncementManager.shared.dismissReminderToast()
    }
}

struct HotkeyReminderToastView: View {
    let shortcut: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.phosphor)
                .accessibilityHidden(true)

            (Text("Press ").foregroundColor(Palette.inkPrimary)
                + Text(shortcut).font(.mono(13, weight: .medium)).foregroundColor(Palette.inkPrimary)
                + Text(" to dictate").foregroundColor(Palette.inkPrimary))
                .font(.system(size: 13, weight: .regular))
                .accessibilityLabel("Tip: press \(shortcut) to start dictation")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Palette.inkSecondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16, height: 16)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 280, maxWidth: 480, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.mtRaise)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Palette.mtLine, lineWidth: 1)
        )
    }
}
