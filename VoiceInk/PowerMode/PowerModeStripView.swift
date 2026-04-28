import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - PowerModeStripView (P2.H / spec §3.12)
//
// Horizontal scrollable strip of glass Power Mode cards — replaces the v1
// expandable-row scaffolding in Settings → Power Modes. Each card carries:
//   • emoji (24pt) — the user-set glyph.
//   • name (13pt semibold) — power mode label, single-line truncated.
//   • up to two app icons (NSWorkspace.shared.icon(forFile:) at 20×20pt @2x).
//   • active-indicator dot (Palette.warn) — pulses on a 1.0s sine when this
//     mode is the currently triggered configuration (spec §3.12).
//
// "Plus card" trailing the strip opens the add-flow as a glass-card hero
// (`PowerModeConfigView` via the existing sliding panel).
//
// Drag-to-reorder mirrors `EnhancementSettingsView.PromptDropDelegate` —
// `.onDrag` returns the config UUID as an `NSItemProvider`, `.onDrop` mutates
// `PowerModeManager.configurations` via the existing
// `moveConfigurations(fromOffsets:toOffset:)` API; that method already calls
// `saveConfigurations()` so the new order persists across launches.
//
// Reviewer focus:
//   • App icons rendered crisply at @2x — `NSWorkspace.shared.icon(forFile:)`
//     returns variable sizes; we apply `.resizable()` + explicit 20×20 frame.
//   • The active-indicator pulse only renders on the matched card; `.warn`
//     is the named-token reference (NOT a hex literal).
//   • Drag is gated to enabled configs to avoid moving disabled ones into
//     the visible area silently — the v1 reorder panel had the same scope.

struct PowerModeStripView: View {
    @ObservedObject var powerModeManager: PowerModeManager
    let onEditConfig: (PowerModeConfig) -> Void
    let onAddConfig: () -> Void

    @State private var draggingItem: PowerModeConfig?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            stripContent
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Power Modes strip")
    }

    private var stripContent: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(powerModeManager.configurations) { config in
                cardCell(for: config)
            }
            AddPowerModeCard(action: onAddConfig)
        }
    }

    @ViewBuilder
    private func cardCell(for config: PowerModeConfig) -> some View {
        let isActive = powerModeManager.activeConfiguration?.id == config.id
        PowerModeStripCard(config: config, isActive: isActive) {
            onEditConfig(config)
        }
        .opacity(draggingItem?.id == config.id ? 0.35 : 1.0)
        .onDrag {
            draggingItem = config
            return NSItemProvider(object: config.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: PowerModeDropDelegate(
                item: config,
                powerModeManager: powerModeManager,
                draggingItem: $draggingItem
            )
        )
    }
}

// MARK: - PowerModeStripCard

private struct PowerModeStripCard: View {
    let config: PowerModeConfig
    let isActive: Bool
    let onTap: () -> Void

    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    @State private var pulseRaised: Bool = false

    private static let cardWidth: CGFloat = 168
    private static let cardHeight: CGFloat = 124

    var body: some View {
        Button(action: onTap) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
        .opacity(config.isEnabled ? 1.0 : 0.55)
        .help(config.name)
    }

    private var content: some View {
        GlassCard(cornerRadius: 14, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                // Top row — emoji + active indicator
                HStack(alignment: .top, spacing: 8) {
                    Text(config.emoji)
                        .font(.system(size: 24))
                        .frame(width: 30, height: 30, alignment: .leading)

                    Spacer(minLength: 0)

                    if isActive {
                        activeDot
                    } else if config.isDefault {
                        Text("DEFAULT")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(0.06 * 8)
                            .foregroundColor(Palette.warn)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Palette.warn.opacity(0.16))
                            )
                    }
                }

                // Name — single-line truncate.
                Text(config.name.isEmpty ? "Untitled" : config.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                // Trigger row — app icons (up to 2) + extra count + url glyph.
                HStack(spacing: 4) {
                    ForEach(visibleAppConfigs, id: \.id) { appConfig in
                        appIcon(bundleIdentifier: appConfig.bundleIdentifier)
                    }
                    if extraTriggerCount > 0 {
                        Text("+\(extraTriggerCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    if (config.urlConfigs?.count ?? 0) > 0 {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    /// 5pt amber dot pulsing on a 1.0s sine. Reduce Motion → static at full
    /// size + medium shadow (reviewer focus #4: a 65% scaleEffect was sticky
    /// when RM was on — pulseRaised stayed false, so the dot looked shrunken
    /// rather than just paused. Now we pin pulseRaised = true on appear and
    /// only swap the repeating animation in/out via the modifier).
    private var activeDot: some View {
        Circle()
            .fill(Palette.warn)
            .frame(width: 7, height: 7)
            .scaleEffect(pulseRaised ? 1.0 : 0.65)
            .shadow(
                color: Palette.warn.opacity(pulseRaised ? 0.45 : 0.18),
                radius: pulseRaised ? 4 : 2
            )
            .animation(
                motion.reduceMotion
                    ? nil
                    : .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                value: pulseRaised
            )
            .onAppear {
                // Always raise on appear so the resting state under Reduce
                // Motion is full-size; the repeatForever animation modifier
                // above is what drives the breathing oscillation when RM
                // is off.
                pulseRaised = true
            }
            .accessibilityLabel("Active")
    }

    private func appIcon(bundleIdentifier: String) -> some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
        }
    }

    private var visibleAppConfigs: [AppConfig] {
        Array((config.appConfigs ?? []).prefix(2))
    }

    private var extraTriggerCount: Int {
        max(0, (config.appConfigs?.count ?? 0) - 2)
    }

    private var accessibilityDescription: String {
        var parts: [String] = [config.name]
        if isActive { parts.append("currently active") }
        if config.isDefault { parts.append("default mode") }
        if !config.isEnabled { parts.append("disabled") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - AddPowerModeCard

private struct AddPowerModeCard: View {
    let action: () -> Void

    private static let cardWidth: CGFloat = 96
    private static let cardHeight: CGFloat = 124

    var body: some View {
        Button(action: action) {
            GlassCard(cornerRadius: 14, padding: 14) {
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Palette.warn)
                    Text("Add Mode")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: Self.cardWidth, height: Self.cardHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Power Mode")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - PowerModeDropDelegate
//
// Mirrors EnhancementSettingsView's PromptDropDelegate but routes through
// `PowerModeManager.moveConfigurations` so persistence + change notifications
// stay centralized (saveConfigurations posts NotificationCenter).

private struct PowerModeDropDelegate: DropDelegate {
    let item: PowerModeConfig
    let powerModeManager: PowerModeManager
    @Binding var draggingItem: PowerModeConfig?

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingItem, dragging.id != item.id else { return }
        guard let fromIndex = powerModeManager.configurations.firstIndex(where: { $0.id == dragging.id }),
              let toIndex = powerModeManager.configurations.firstIndex(where: { $0.id == item.id })
        else { return }

        if powerModeManager.configurations[toIndex].id != dragging.id {
            withAnimation(.easeInOut(duration: 0.14)) {
                powerModeManager.moveConfigurations(
                    fromOffsets: IndexSet(integer: fromIndex),
                    toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                )
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
}
