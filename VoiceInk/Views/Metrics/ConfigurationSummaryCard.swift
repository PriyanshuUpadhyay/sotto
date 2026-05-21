import SwiftUI
import KeyboardShortcuts

// MARK: - ConfigurationSummaryCard (W14C)
//
// Top-of-Dashboard "what's configured" card. Read-only mirror of the most
// relevant configured items. Lives between hero and metrics on the default
// landing pane (`MetricsContent`) so a user can scan the active setup
// without clicking through 11 sidebar entries.
//
// Reuses the existing `SettingsCard` idiom — does NOT introduce a new card
// type. Rows use a small file-private `SummaryRow` (icon-tile + label +
// trailing value), kept private here per the W14E micro-rule: don't promote
// to a shared component until a third caller appears.
//
// Sources are read-only against:
//   - `transcriptionModelManager.currentTranscriptionModel?.displayName`
//   - `enhancementService.enhanceLevel.displayName`
//   - `enhancementService.aiService.{selectedProvider,currentModel,connectedProviders}`
//   - `enhancementService.activeLocalPathDescription` (W11.B)
//   - `hotkeyManager.selectedHotkey1` + `KeyboardShortcuts.getShortcut(...)`
//   - `PowerModeManager.shared.enabledConfigurations.count` (gated on
//     `@AppStorage("powerModeUIFlag")` so a hidden Power Mode pane doesn't
//     surface a meaningless row).
//
// No writes, no W11/W14A/W14B routing changes.

struct ConfigurationSummaryCard: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @AppStorage("powerModeUIFlag") private var powerModeUIFlag = false

    var body: some View {
        SettingsCard(
            iconSystemName: "checkmark.seal",
            iconTint: Palette.brandAcid,
            title: "What's configured",
            subtitle: "At-a-glance view of the active setup."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SummaryRow(
                    icon: "waveform.circle.fill",
                    label: "Transcription model",
                    value: transcriptionModelDisplay
                )
                SummaryRow(
                    icon: "wand.and.stars",
                    label: "Enhancement",
                    value: enhancementService.enhanceLevel.displayName
                )
                SummaryRow(
                    icon: "sparkles.rectangle.stack",
                    label: "LLM provider",
                    value: providerDisplay
                )
                SummaryRow(
                    icon: "command",
                    label: "Primary hotkey",
                    value: primaryHotkeyDisplay
                )
                SummaryRow(
                    icon: "cpu",
                    label: "Local AI path",
                    value: enhancementService.activeLocalPathDescription
                )
                if powerModeUIFlag {
                    SummaryRow(
                        icon: "bolt.fill",
                        label: "Power Mode",
                        value: powerModeDisplay
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Source projections

    private var transcriptionModelDisplay: String {
        transcriptionModelManager.currentTranscriptionModel?.displayName ?? "None selected"
    }

    private var providerDisplay: String {
        if enhancementService.aiService.connectedProviders.isEmpty {
            return "Not connected"
        }
        let provider = enhancementService.aiService.selectedProvider
        let providerName = ProviderChipStyle.displayName(for: provider)
        let model = enhancementService.aiService.currentModel
        return model.isEmpty ? providerName : "\(providerName) — \(model)"
    }

    /// Renders the active hotkey as compact glyphs. Inlined from
    /// `SettingsView.keyComboGlyphs` rather than promoted to a shared helper
    /// (W14E micro-rule: 3-callers minimum before promotion). The single-
    /// modifier path covers 7 of 9 `HotkeyOption` cases; only `.custom`
    /// needs the `KeyboardShortcuts.Shortcut` parse and `.none` returns
    /// the literal "None".
    private var primaryHotkeyDisplay: String {
        switch hotkeyManager.selectedHotkey1 {
        case .none:
            return "None"
        case .rightOption, .leftOption:
            return "⌥"
        case .leftControl, .rightControl:
            return "⌃"
        case .fn:
            return "fn"
        case .rightCommand:
            return "⌘"
        case .rightShift:
            return "⇧"
        case .custom:
            guard let s = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) else {
                return "Custom"
            }
            return s.description
        }
    }

    private var powerModeDisplay: String {
        let n = powerModeManager.enabledConfigurations.count
        return n > 0 ? "\(n) enabled" : "Disabled"
    }
}

// MARK: - SummaryRow (file-private)
//
// Single-line row: small icon-tile + label + trailing value. Visually
// distinct from `SettingsRow` (which has trailing controls / pickers); this
// one is read-only and right-aligns the value text. Kept file-private —
// not promoted to a shared component until a third caller appears.

private struct SummaryRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.brandAcid.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Palette.brandAcid.opacity(0.28), lineWidth: 0.5)
                )
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Palette.brandAcid)
                )
                .frame(width: 22, height: 22)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
