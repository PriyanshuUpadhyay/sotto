import SwiftUI

// MARK: - Read-only seam

/// Read-only projection of permission state: getters plus a no-prompt refresh,
/// and nothing else. It refines `ObservableObject` so a SwiftUI view can observe
/// it directly while still being unable to name a request API — the Settings
/// status strip is read-only by construction at the view layer, not just the model.
protocol PermissionStatusReading: ObservableObject {
    var audioGranted: Bool { get }
    var accessibilityGranted: Bool { get }
    var screenRecordingGranted: Bool { get }
    func refreshStatus()
}

extension PermissionManager: PermissionStatusReading {
    var audioGranted: Bool { audioPermissionStatus == .authorized }
    var accessibilityGranted: Bool { isAccessibilityEnabled }
    var screenRecordingGranted: Bool { isScreenRecordingEnabled }
    func refreshStatus() { checkAllPermissions() }
}

// MARK: - Pure derived row state

struct PermissionStatusRows: Equatable {
    let microphone: Bool
    let accessibility: Bool
    let screenRecording: Bool

    init(microphone: Bool, accessibility: Bool, screenRecording: Bool) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }

    init<Source: PermissionStatusReading>(reading source: Source) {
        self.init(
            microphone: source.audioGranted,
            accessibility: source.accessibilityGranted,
            screenRecording: source.screenRecordingGranted
        )
    }
}

// MARK: - Lifecycle model

struct PermissionsStatusStripModel<Source: PermissionStatusReading> {
    let source: Source

    var rows: PermissionStatusRows { PermissionStatusRows(reading: source) }

    func onAppear() {
        source.refreshStatus()
    }
}

// MARK: - View

struct PermissionsStatusStrip<Source: PermissionStatusReading>: View {
    @ObservedObject var source: Source

    private var model: PermissionsStatusStripModel<Source> {
        PermissionsStatusStripModel(source: source)
    }

    var body: some View {
        let rows = model.rows
        SettingsCard(
            iconSystemName: "lock.shield",
            iconTint: Palette.neutral,
            title: "Permissions",
            subtitle: "System access Sotto currently holds."
        ) {
            permissionRow(icon: "mic.fill", label: "Microphone", granted: rows.microphone)
            permissionRow(icon: "accessibility", label: "Accessibility", granted: rows.accessibility)
            permissionRow(icon: "rectangle.dashed.badge.record", label: "Screen Recording", granted: rows.screenRecording)
        }
        .onAppear { model.onAppear() }
    }

    private func permissionRow(icon: String, label: String, granted: Bool) -> some View {
        SettingsRow(
            iconSystemName: icon,
            label: label,
            iconTint: Palette.neutral
        ) {
            statusPill(granted: granted)
        }
    }

    private func statusPill(granted: Bool) -> some View {
        let tone = granted ? Palette.success : Palette.warn
        return Label(granted ? "Granted" : "Not granted",
                     systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tone)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tone.opacity(0.16)))
            .overlay(Capsule().stroke(tone.opacity(0.42), lineWidth: 0.5))
    }
}
