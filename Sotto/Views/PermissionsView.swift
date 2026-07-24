import SwiftUI
import AVFoundation
import Cocoa

class PermissionManager: ObservableObject {
    @Published var audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var isAccessibilityEnabled = false
    @Published var isScreenRecordingEnabled = false

    init() {
        // Start observing system events that might indicate permission changes
        setupNotificationObservers()
        
        // Initial permission checks
        checkAllPermissions()
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotificationObservers() {
        // Only observe when app becomes active, as this is a likely time for permissions to have changed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func applicationDidBecomeActive() {
        checkAllPermissions()
    }
    
    func checkAllPermissions() {
        checkAccessibilityPermissions()
        checkScreenRecordingPermission()
        checkAudioPermissionStatus()
    }
    
    func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async {
            self.isAccessibilityEnabled = accessibilityEnabled
        }
    }
    
    func checkScreenRecordingPermission() {
        DispatchQueue.main.async {
            self.isScreenRecordingEnabled = CGPreflightScreenCaptureAccess()
        }
    }
    
    @discardableResult
    func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    func checkAudioPermissionStatus() {
        DispatchQueue.main.async {
            self.audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }
    
    func requestAudioPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.audioPermissionStatus = granted ? .authorized : .denied
            }
        }
    }
}

// MARK: - PermissionRow
//
// Reusable per-permission row primitive — icon + title + description + status
// pill + (optional) CTA button. Consumed by the ONBOARDING permissions step,
// which composes its own outer chrome. No outer card / material wrapping here —
// the host owns the surface.
struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let buttonTitle: String
    let buttonAction: () -> Void
    let checkPermission: () -> Void
    var infoTipMessage: String?
    var infoTipLink: String?
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // Icon with background
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((isGranted ? Palette.success : Palette.warn).opacity(0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke((isGranted ? Palette.success : Palette.warn).opacity(0.36), lineWidth: 0.5)
                        )

                    Image(systemName: isGranted ? "\(icon).fill" : icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isGranted ? Palette.success : Palette.warn)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(Palette.inkPrimary)
                        if let message = infoTipMessage {
                            if let link = infoTipLink, !link.isEmpty {
                                InfoTip(message, learnMoreURL: link)
                            } else {
                                InfoTip(message)
                            }
                        }
                    }
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(Palette.inkSecondary)
                }

                Spacer()

                // Status indicator with refresh
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(Animation.haloExpand) {
                            isRefreshing = true
                        }
                        checkPermission()

                        // Reset the animation after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isRefreshing = false
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Palette.inkSecondary)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    StatusPill(
                        text: isGranted ? "Granted" : "Needs Access",
                        tone: isGranted ? .positive : .warning
                    )
                }
            }

            if !isGranted {
                Button(action: buttonAction) {
                    HStack {
                        Text(buttonTitle)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(OnboardingPhosphorButtonStyle(
                    horizontalPadding: 16,
                    verticalPadding: 12
                ))
            }
        }
    }
}

// MARK: - StatusPill
//
// Small capsule-pill rendering availability state in the Halo palette
// (success-green / warn-amber / neutral-gray). Consumed by `PermissionRow`.

struct StatusPill: View {
    enum Tone {
        case positive   // green — connected, available
        case negative   // red-tinted — disconnected, error
        case neutral    // gray — no signal
        case warning    // amber — degraded, checking

        var color: Color {
            switch self {
            case .positive: return Palette.success
            case .negative: return Brand.tint
            case .neutral:  return Palette.neutral
            case .warning:  return Palette.warn
            }
        }
    }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tone.color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(tone.color.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(tone.color.opacity(0.32), lineWidth: 0.5)
        )
    }
}
