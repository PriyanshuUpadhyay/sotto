import SwiftUI
import AppKit
import AVFoundation

// MARK: - Status seam

/// Read-only projection of permission state: getters plus a no-prompt refresh.
/// It refines `ObservableObject` so a SwiftUI view can observe it directly. The
/// derived-row model reads only through this seam; requesting access is a
/// separate `PermissionRequesting` refinement (below) the strip's rows drive.
protocol PermissionStatusReading: ObservableObject {
    var audioGranted: Bool { get }
    var accessibilityGranted: Bool { get }
    var screenRecordingGranted: Bool { get }
    func refreshStatus()
}

/// Request-capable refinement: the read-only getters plus the raw microphone
/// status and the per-permission request entry points. A not-granted row in the
/// Settings strip taps straight into these.
protocol PermissionRequesting: PermissionStatusReading {
    var audioStatus: AVAuthorizationStatus { get }
    func requestAudioPermission()
    func requestAccessibilityPermission()
    @discardableResult func requestScreenRecordingPermission() -> Bool
}

extension PermissionManager: PermissionRequesting {
    var audioGranted: Bool { audioPermissionStatus == .authorized }
    var accessibilityGranted: Bool { isAccessibilityEnabled }
    var screenRecordingGranted: Bool { isScreenRecordingEnabled }
    var audioStatus: AVAuthorizationStatus { audioPermissionStatus }
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

struct PermissionsStatusStrip<Source: PermissionRequesting>: View {
    @ObservedObject var source: Source

    private enum Permission {
        case microphone, accessibility, screenRecording
    }

    private var model: PermissionsStatusStripModel<Source> {
        PermissionsStatusStripModel(source: source)
    }

    var body: some View {
        let rows = model.rows
        SettingsCard(
            iconSystemName: "lock.shield",
            iconTint: Palette.neutral,
            title: "Permissions",
            subtitle: "System access Sotto currently holds. Tap a row to grant."
        ) {
            permissionRow(icon: "mic.fill", label: "Microphone", granted: rows.microphone, permission: .microphone)
            permissionRow(icon: "accessibility", label: "Accessibility", granted: rows.accessibility, permission: .accessibility)
            permissionRow(icon: "rectangle.dashed.badge.record", label: "Screen Recording", granted: rows.screenRecording, permission: .screenRecording)
        }
        .onAppear { model.onAppear() }
    }

    @ViewBuilder
    private func permissionRow(icon: String, label: String, granted: Bool, permission: Permission) -> some View {
        let row = SettingsRow(
            iconSystemName: icon,
            label: label,
            iconTint: Palette.neutral
        ) {
            statusPill(granted: granted)
        }

        if granted {
            row
        } else {
            Button { request(permission) } label: {
                row.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }

    private func statusPill(granted: Bool) -> some View {
        let tone = granted ? Palette.success : Palette.warn
        return HStack(spacing: 6) {
            Label(granted ? "Granted" : "Not granted",
                  systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tone)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(tone.opacity(0.16)))
                .overlay(Capsule().stroke(tone.opacity(0.42), lineWidth: 0.5))
            if !granted {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func request(_ permission: Permission) {
        switch permission {
        case .microphone:
            if source.audioStatus == .notDetermined {
                source.requestAudioPermission()
            } else {
                openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            }
        case .accessibility:
            source.requestAccessibilityPermission()
        case .screenRecording:
            if !source.requestScreenRecordingPermission() {
                openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            }
        }
        source.refreshStatus()
    }

    private func openSettings(_ raw: String) {
        if let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }
}
