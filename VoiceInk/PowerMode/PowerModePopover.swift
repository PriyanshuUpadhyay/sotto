import SwiftUI
import AppKit

// MARK: - PowerModePopover (P2.H / spec §3.12)
//
// Glass-treatment popover anchored to `RecorderPowerModeButton` on the
// constellation orb's chip. Three-zone layout per spec §3.12:
//   1. Active mode hero — large emoji + name + app icon + mono caption
//      ("Auto-detected from <app>" when there is a frontmost app match).
//   2. Quick-switch list — remaining enabled modes as glass rows. Tapping
//      a row sets the active configuration and begins a session via
//      `PowerModeSessionManager` (preserved v1 behavior).
//   3. Footer — "Configure Power Modes" jumps to Settings → Power Modes.
//
// Glass layering note (lead reviewer focus):
//   The hosting `.popover(isPresented:)` already paints an NSPopover with
//   its own vibrant chrome. Stacking another `HaloMaterial` on top would
//   double-blur and muddle the surface. We instead render the hero on a
//   `GlassCard` pinned to `appearance: .light` (a higher-key translucent
//   variant that contrasts cleanly against the popover's onyx vibrancy)
//   and keep the rest of the layout flat — no outer HaloMaterial wrapper.
//
// All existing functionality preserved:
//   • setActiveConfiguration on selection.
//   • PowerModeSessionManager.beginSession(with:) on apply.
//   • selectedConfig syncs with `powerModeManager.activeConfiguration`
//     when changed externally (auto-detect / hotkey).

struct PowerModePopover: View {
    @ObservedObject var powerModeManager = PowerModeManager.shared
    @State private var selectedConfig: PowerModeConfig?

    /// Optional callback fired when the user taps "Configure Power Modes".
    /// When present, the host (recorder button) is responsible for routing to
    /// Settings → Power Modes. Default behavior posts a NotificationCenter
    /// event that `VoiceInk.swift` already wires for Settings navigation.
    var onConfigure: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroSection
            Divider().opacity(0.4)
            quickSwitchSection
            footer
        }
        .padding(14)
        .frame(width: 280)
        .frame(maxHeight: 420)
        .background(Color.black.opacity(0.001)) // hit region; popover paints its own chrome
        // No forced colorScheme — let the NSPopover's vibrant chrome drive
        // primary/secondary text colors (reviewer focus #5: forcing .dark
        // while the hero uses GlassCard(.light) muddled the contrast).
        .onAppear {
            selectedConfig = powerModeManager.activeConfiguration
        }
        .onChange(of: powerModeManager.activeConfiguration) { _, newValue in
            selectedConfig = newValue
        }
    }

    // MARK: - Hero (active mode)

    @ViewBuilder
    private var heroSection: some View {
        if let active = selectedConfig {
            GlassCard(cornerRadius: 14, padding: 14, appearance: .light) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(active.emoji)
                            .font(.system(size: 28))
                            .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(active.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Text(autoDetectedCaption(for: active))
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        Spacer(minLength: 0)

                        if let bundleId = firstAppBundleIdentifier(active) {
                            heroAppIcon(bundleIdentifier: bundleId)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("No active Power Mode")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.92))
                Text("Pick one below or configure context detection.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func heroAppIcon(bundleIdentifier: String) -> some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            } else {
                EmptyView()
            }
        }
    }

    private func autoDetectedCaption(for config: PowerModeConfig) -> String {
        if let app = NSWorkspace.shared.frontmostApplication?.localizedName {
            return "AUTO · \(app.uppercased())"
        }
        return config.isDefault ? "DEFAULT" : "ACTIVE"
    }

    private func firstAppBundleIdentifier(_ config: PowerModeConfig) -> String? {
        config.appConfigs?.first?.bundleIdentifier
    }

    // MARK: - Quick switch

    private var quickSwitchSection: some View {
        let others = powerModeManager.configurations.filter {
            $0.isEnabled && $0.id != selectedConfig?.id
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text("SWITCH")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            if others.isEmpty {
                Text(emptyStateText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(others) { config in
                            PowerModePopoverRow(config: config) {
                                applyConfig(config)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private var emptyStateText: String {
        if powerModeManager.configurations.isEmpty {
            return "No Power Modes yet."
        }
        return "Only one Power Mode enabled."
    }

    // MARK: - Footer

    private var footer: some View {
        Button {
            (onConfigure ?? Self.defaultConfigureAction)()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                Text("Configure Power Modes")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Configure Power Modes")
    }

    // MARK: - Actions

    private func applyConfig(_ config: PowerModeConfig) {
        powerModeManager.setActiveConfiguration(config)
        selectedConfig = config
        Task {
            await PowerModeSessionManager.shared.beginSession(with: config)
        }
    }

    private static func defaultConfigureAction() {
        // Mirror MenuBarManager.openMainWindowAndNavigate semantics — bring the
        // main window forward (popover lives in a separate panel, so the main
        // window may be hidden when isMenuBarOnly is on), then post
        // .navigateToDestination so ContentView's onReceive switches to the
        // Power Mode tab. Reviewer focus #1: the v1 OpenSettingsRequest path
        // had no observer; the canonical opener uses .navigateToDestination.
        NSApplication.shared.setActivationPolicy(.regular)
        _ = WindowManager.shared.showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: .navigateToDestination,
                object: nil,
                userInfo: ["destination": "Power Mode"]
            )
        }
    }
}

// MARK: - PowerModePopoverRow

private struct PowerModePopoverRow: View {
    let config: PowerModeConfig
    let action: () -> Void

    @State private var hovering: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(config.emoji)
                    .font(.system(size: 16))
                    .frame(width: 24, height: 24)

                Text(config.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if config.isDefault {
                    Text("DEFAULT")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Palette.warn)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Palette.warn.opacity(0.16))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.10 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(hovering ? 0.16 : 0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Switch to \(config.name)")
        .accessibilityAddTraits(.isButton)
    }
}
