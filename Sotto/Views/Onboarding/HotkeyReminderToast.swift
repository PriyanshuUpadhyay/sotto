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
            Text("›")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(Palette.brandAcid)
                .accessibilityHidden(true)

            Text("Press \(shortcut) to dictate")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(Palette.onyxFg)
                .accessibilityLabel("Tip: press \(shortcut) to start dictation")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Palette.onyxMute)
            }
            .buttonStyle(.plain)
            .frame(width: 16, height: 16)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 280, maxWidth: 480, minHeight: 44)
        .background(
            TacticalGlass(
                shape: RoundedRectangle(cornerRadius: SottoGeometry.cornerRadiusNotch, style: .continuous),
                phase: .armed
            )
        )
    }
}
