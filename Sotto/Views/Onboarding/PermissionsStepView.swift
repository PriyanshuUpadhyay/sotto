import SwiftUI
import AVFoundation
import AppKit

struct PermissionsStepView: View {
    let onContinue: () -> Void

    @StateObject private var perms = PermissionManager()
    @State private var stage: PermissionStage = .microphone

    private var currentGranted: Bool {
        switch stage {
        case .microphone: return perms.audioPermissionStatus == .authorized
        case .accessibility: return perms.isAccessibilityEnabled
        case .screenRecording: return perms.isScreenRecordingEnabled
        }
    }

    private var canAdvance: Bool {
        stage.canAdvance(granted: currentGranted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("› PERMISSIONS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.76)
                .foregroundColor(Palette.brandAcid)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 30)

            Text("Step \(stage.rawValue + 1) of \(PermissionStage.allCases.count)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(Palette.onyxMute)

            Text(headline)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(Palette.onyxFg)

            Text(subtitle)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(Palette.onyxMute)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 4)

            permissionRow
                .id(stage)

            Spacer()

            footer
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear { perms.checkAllPermissions() }
    }

    private var permissionRow: some View {
        PermissionRow(
            icon: rowIcon,
            title: rowTitle,
            description: rowDescription,
            isGranted: currentGranted,
            buttonTitle: rowButtonTitle,
            buttonAction: { performRequest() },
            checkPermission: { perms.checkAllPermissions() },
            infoTipMessage: rowInfoTip
        )
    }

    private var footer: some View {
        HStack {
            if !stage.isRequired {
                Button(action: skip) {
                    Text("Skip for now ›")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(Palette.onyxMute)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Continues without granting this permission")
            }

            Spacer()

            Button(action: advance) {
                Text(continueLabel)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(canAdvance ? Palette.brandAcid : Palette.onyxMute)
                    .frame(width: 150, height: 38)
                    .background(
                        TacticalGlass(
                            shape: RoundedRectangle(cornerRadius: SottoGeometry.cornerRadiusNotch, style: .continuous),
                            phase: canAdvance ? .armed : .hidden
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
            .accessibilityHint(stage.isRequired && !currentGranted ? "Grant microphone access to continue" : "")
        }
    }

    private var continueLabel: String {
        stage.next() == nil ? "▸ Continue" : "▸ Next"
    }

    private func advance() {
        guard canAdvance else { return }
        if let nextStage = stage.next() {
            stage = nextStage
        } else {
            onContinue()
        }
    }

    private func skip() {
        OnboardingState.shared.markSkippedPermissions()
        if let nextStage = stage.next() {
            stage = nextStage
        } else {
            onContinue()
        }
    }

    private func performRequest() {
        switch stage {
        case .microphone:
            if perms.audioPermissionStatus == .notDetermined {
                perms.requestAudioPermission()
            } else {
                openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            }
        case .accessibility:
            openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording:
            perms.requestScreenRecordingPermission()
            openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }

    private func openSettings(_ raw: String) {
        if let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }

    private var headline: String {
        switch stage {
        case .microphone: return "Allow microphone access"
        case .accessibility: return "Allow accessibility access"
        case .screenRecording: return "Allow screen recording"
        }
    }

    private var subtitle: String {
        switch stage {
        case .microphone:
            return "Required — Sotto records your voice to transcribe it. Dictation cannot start without it."
        case .accessibility:
            return "Recommended — lets Sotto paste transcribed text at your cursor in any app."
        case .screenRecording:
            return "Recommended — uses on-screen context to improve transcription accuracy."
        }
    }

    private var rowIcon: String {
        switch stage {
        case .microphone: return "mic"
        case .accessibility: return "hand.raised"
        case .screenRecording: return "rectangle.on.rectangle"
        }
    }

    private var rowTitle: String {
        switch stage {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }

    private var rowDescription: String {
        switch stage {
        case .microphone: return "Record your voice for transcription."
        case .accessibility: return "Paste transcribed text at your cursor across apps."
        case .screenRecording: return "Use screen context to improve accuracy."
        }
    }

    private var rowButtonTitle: String {
        switch stage {
        case .microphone:
            return perms.audioPermissionStatus == .notDetermined ? "Request Permission" : "Open System Settings"
        case .accessibility:
            return "Open System Settings"
        case .screenRecording:
            return "Request Permission"
        }
    }

    private var rowInfoTip: String? {
        switch stage {
        case .microphone:
            return nil
        case .accessibility:
            return "Sotto uses Accessibility to paste transcribed text directly at your cursor in any app."
        case .screenRecording:
            return "Sotto reads on-screen text to improve accuracy. It is processed locally and never stored."
        }
    }
}
