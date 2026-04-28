import SwiftUI
import AVFoundation
import AppKit
import KeyboardShortcuts

// MARK: - OnboardingPermissionsView (P2.G)
//
// Vertical scroll of glass-card permission rows. Each row exposes:
//   [tinted icon tile] [title + description] [status pill]
//   ↳ inline picker (audio device / keyboard shortcut), or
//   ↳ right-aligned action button (Enable Access)
//
// Status pill: granted = `Palette.success`, pending = `Palette.warn` (acceptance
// criteria, plan §P2.G). Continue gates on either all-granted *or* user opt-in.
// The previous one-at-a-time stepper is replaced — all five permissions are
// now visible at once so users can self-pace.
//
// Permission-request switch + audio device + hotkey logic preserved verbatim
// from the v1 file (only the layout shell changed) — keeps the "permissions
// actually grant, models actually download" reviewer focus intact.

struct OnboardingPermission: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let tint: Color
    let type: PermissionType

    enum PermissionType {
        case microphone
        case audioDeviceSelection
        case accessibility
        case screenRecording
        case keyboardShortcut
    }
}

struct OnboardingPermissionsView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared
    @State private var permissionStates: [Bool] = [false, false, false, false, false]
    @State private var showModelDownload = false

    private let permissions: [OnboardingPermission] = [
        .init(title: "Microphone Access",
              description: "Enable your microphone so VoiceInk can capture audio.",
              icon: "mic.fill",
              tint: Palette.recording,
              type: .microphone),
        .init(title: "Microphone Selection",
              description: "Pick the audio input device VoiceInk should listen to.",
              icon: "headphones",
              tint: Palette.transcribe,
              type: .audioDeviceSelection),
        .init(title: "Accessibility Access",
              description: "Allow VoiceInk to type into the focused app on your Mac.",
              icon: "accessibility",
              tint: Palette.enhance,
              type: .accessibility),
        .init(title: "Screen Recording",
              description: "Adds on-screen context to improve transcription accuracy.",
              icon: "rectangle.inset.filled.and.person.filled",
              tint: Palette.transcribe,
              type: .screenRecording),
        .init(title: "Keyboard Shortcut",
              description: "Choose a hotkey to summon VoiceInk from anywhere.",
              icon: "command",
              tint: Palette.warn,
              type: .keyboardShortcut)
    ]

    private var allGranted: Bool { permissionStates.allSatisfy { $0 } }

    var body: some View {
        ZStack {
            OnboardingBackgroundView().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    header
                    VStack(spacing: 14) {
                        ForEach(Array(permissions.enumerated()), id: \.element.id) { index, perm in
                            permissionCard(index: index, perm: perm)
                        }
                    }
                    continueRow
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }

            if showModelDownload {
                OnboardingModelDownloadView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onAppear {
            checkExistingPermissions()
            audioDeviceManager.loadAvailableDevices()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Permissions")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.55))

            Text("Set Up VoiceInk")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Grant the permissions VoiceInk needs to listen, transcribe, and paste.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding(.top, 12)
    }

    // MARK: - Card per permission

    @ViewBuilder
    private func permissionCard(index: Int, perm: OnboardingPermission) -> some View {
        GlassCard(cornerRadius: 16, padding: 16, appearance: .onyx) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    iconTile(systemName: perm.icon, tint: perm.tint)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(perm.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            if perm.type == .screenRecording {
                                InfoTip(
                                    "VoiceInk reads on-screen text to improve transcription accuracy. Processed locally; not stored.",
                                    learnMoreURL: "https://tryvoiceink.com/docs/contextual-awareness"
                                )
                            }
                        }
                        Text(perm.description)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    statusPill(granted: permissionStates[index])
                        .padding(.top, 2)
                }

                // Inline pickers / action — type-driven.
                Group {
                    switch perm.type {
                    case .audioDeviceSelection:
                        audioDeviceInline(index: index)
                    case .keyboardShortcut:
                        keyboardShortcutInline(index: index)
                    default:
                        if !permissionStates[index] {
                            HStack {
                                Spacer()
                                actionButton(title: actionTitle(for: perm), index: index)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func iconTile(systemName: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(tint.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(tint.opacity(0.32), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tint)
            )
            .frame(width: 36, height: 36)
    }

    private func statusPill(granted: Bool) -> some View {
        let tone: Color = granted ? Palette.success : Palette.warn
        let label: String = granted ? "GRANTED" : "PENDING"
        return Text(label)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.6)
            .foregroundColor(tone)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tone.opacity(0.14)))
            .overlay(Capsule().stroke(tone.opacity(0.36), lineWidth: 0.5))
            .accessibilityLabel(granted ? "Granted" : "Pending")
    }

    private func actionButton(title: String, index: Int) -> some View {
        Button {
            requestPermission(index: index)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.accentColor))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func actionTitle(for perm: OnboardingPermission) -> String {
        switch perm.type {
        case .screenRecording: return "Open Settings"
        case .accessibility:   return "Open Settings"
        default:               return "Enable Access"
        }
    }

    // MARK: - Continue

    private var continueRow: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.haloExpand) { showModelDownload = true }
            } label: {
                Text(allGranted ? "Continue" : "Continue Anyway")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(width: 220, height: 46)
                    .background(Color.white.opacity(allGranted ? 1.0 : 0.85))
                    .cornerRadius(23)
            }
            .buttonStyle(ScaleButtonStyle())

            SkipButton(text: "Skip All") {
                withAnimation(.haloExpand) { showModelDownload = true }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Inline pickers

    @ViewBuilder
    private func audioDeviceInline(index: Int) -> some View {
        if audioDeviceManager.availableDevices.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "mic.slash.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text("No microphones found")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            }
        } else {
            styledPicker(
                label: "Microphone:",
                selectedValue: audioDeviceManager.selectedDeviceID ?? 0,
                displayValue: audioDeviceManager.availableDevices.first { $0.id == audioDeviceManager.selectedDeviceID }?.name ?? "Select Device",
                options: audioDeviceManager.availableDevices.map { $0.id },
                optionDisplayName: { deviceId in
                    audioDeviceManager.availableDevices.first { $0.id == deviceId }?.name ?? "Unknown Device"
                },
                onSelection: { deviceId in
                    audioDeviceManager.selectDevice(id: deviceId)
                    audioDeviceManager.selectInputMode(.custom)
                    permissionStates[index] = true
                }
            )
            .onAppear {
                if !audioDeviceManager.availableDevices.isEmpty,
                   let deviceID = audioDeviceManager.findBestAvailableDevice() {
                    audioDeviceManager.selectDevice(id: deviceID)
                    audioDeviceManager.selectInputMode(.custom)
                    permissionStates[index] = true
                }
            }
        }
    }

    @ViewBuilder
    private func keyboardShortcutInline(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            styledPicker(
                label: "Shortcut:",
                selectedValue: hotkeyManager.selectedHotkey1,
                displayValue: hotkeyManager.selectedHotkey1.displayName,
                options: HotkeyManager.HotkeyOption.allCases.filter { $0 != .none && $0 != .custom },
                optionDisplayName: { $0.displayName },
                onSelection: { option in
                    hotkeyManager.selectedHotkey1 = option
                    permissionStates[index] = option.isModifierKey
                }
            )

            if hotkeyManager.selectedHotkey1 == .custom {
                KeyboardShortcuts.Recorder(for: .toggleMiniRecorder) { newShortcut in
                    permissionStates[index] = newShortcut != nil
                }
                .controlSize(.large)
            }
        }
        .onChange(of: hotkeyManager.selectedHotkey1) { _, newValue in
            permissionStates[index] = newValue != .none
        }
    }

    // MARK: - Permission requests (verbatim from v1)

    private func checkExistingPermissions() {
        permissionStates[0] = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        permissionStates[1] = audioDeviceManager.selectedDeviceID != nil
        permissionStates[2] = AXIsProcessTrusted()
        permissionStates[3] = CGPreflightScreenCaptureAccess()
        permissionStates[4] = hotkeyManager.isShortcutConfigured
    }

    private func requestPermission(index: Int) {
        if permissionStates[index] { return }

        switch permissions[index].type {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.permissionStates[index] = granted
                    if granted {
                        self.audioDeviceManager.loadAvailableDevices()
                    }
                }
            }

        case .audioDeviceSelection:
            audioDeviceManager.loadAvailableDevices()
            if audioDeviceManager.availableDevices.isEmpty {
                audioDeviceManager.selectInputMode(.custom)
                permissionStates[index] = true
                return
            }
            if let deviceID = audioDeviceManager.findBestAvailableDevice() {
                audioDeviceManager.selectDevice(id: deviceID)
                audioDeviceManager.selectInputMode(.custom)
                permissionStates[index] = true
            }

        case .accessibility:
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options)
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    permissionStates[index] = true
                }
            }

        case .screenRecording:
            CGRequestScreenCaptureAccess()
            if let prefpaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(prefpaneURL)
            }
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                if CGPreflightScreenCaptureAccess() {
                    timer.invalidate()
                    permissionStates[index] = true
                }
            }

        case .keyboardShortcut:
            break // user picks via the inline picker
        }
    }

    // MARK: - Styled picker (verbatim from v1, dropped extra outer padding so it nests cleanly inside GlassCard)

    @ViewBuilder
    private func styledPicker<T: Hashable>(
        label: String,
        selectedValue: T,
        displayValue: String,
        options: [T],
        optionDisplayName: @escaping (T) -> String,
        onSelection: @escaping (T) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.75))

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(action: { onSelection(option) }) {
                        HStack {
                            Text(optionDisplayName(option))
                            if selectedValue == option {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(displayValue)
                        .foregroundColor(.white)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
            }
            .menuStyle(.borderlessButton)

            Spacer()
        }
    }
}
