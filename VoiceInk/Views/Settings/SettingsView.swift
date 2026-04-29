import SwiftUI
import Cocoa
import KeyboardShortcuts
import LaunchAtLogin
import AVFoundation

// MARK: - SettingsView (P2.D — glass cards + rich rows)
//
// Per spec §3.3 + plan §P2.D:
//   - Replaces v1 `Form { Section { } }` layout with a `ScrollView { LazyVStack }`
//     of `SettingsCard` glass islands. Each card embeds a `SettingsSectionHeader`
//     + content stack of `SettingsRow`s.
//   - `LabeledContent` is gone from this file (Grep verifies). Each former
//     LabeledContent call site is now a `SettingsRow` with a section-accent
//     icon tile per spec §2.5 iconography table.
//
// Form-chrome mitigation (plan §P2.D risks): we cannot host `SettingsCard`
// inside `Form` — Form's grouped Section background double-layers under the
// glass material. Resolved by stripping `Form` entirely. Layout/spacing for
// each row is now explicit via `SettingsRow` rather than implicit via Form.

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var recorderUIManager: RecorderUIManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @StateObject private var deviceManager = AudioDeviceManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var playbackController = PlaybackController.shared
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 2.0
    @AppStorage("useAppleScriptPaste") private var useAppleScriptPaste = false
    @AppStorage("failedDwellSeconds") private var failedDwellSeconds: Double = 6.0
    @State private var currentShortcut = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)
    @State private var currentShortcut2 = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder2)
    @State private var isCustomCancelEnabled = KeyboardShortcuts.getShortcut(for: .cancelRecorder) != nil

    // Expansion states - all collapsed by default
    @State private var isCustomCancelExpanded = false
    @State private var isMiddleClickExpanded = false
    @State private var isSoundFeedbackExpanded = false
    @State private var isMuteSystemExpanded = false
    @State private var isRestoreClipboardExpanded = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                shortcutsCard
                additionalShortcutsCard
                recordingFeedbackCard
                PowerModeSection()
                interfaceCard
                ExperimentalSection()
                generalCard
                privacyCard
                backupCard
                diagnosticsCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .adaptiveGlassBackground()
    }

    // MARK: - Shortcuts

    private var shortcutsCard: some View {
        SettingsCard(
            iconSystemName: "command",
            iconTint: Palette.accent,
            title: "Shortcuts",
            subtitle: "Trigger recording from anywhere.",
            statusText: hotkeyManager.selectedHotkey2 != .none ? "2 active" : "1 active",
            statusTone: .neutral
        ) {
            SettingsRow(
                iconSystemName: "1.circle",
                label: "Shortcut 1",
                iconTint: Palette.accent
            ) {
                HStack(spacing: 8) {
                    if hotkeyManager.selectedHotkey1 != .none {
                        hotkeyModePicker(binding: $hotkeyManager.hotkeyMode1)
                    }
                    hotkeyPicker(binding: $hotkeyManager.selectedHotkey1)
                    if hotkeyManager.selectedHotkey1 == .custom {
                        KeyboardShortcuts.Recorder(for: .toggleMiniRecorder) { shortcut in
                            currentShortcut = shortcut
                        }
                        .controlSize(.small)
                    }
                    let glyphs = keyComboGlyphs(
                        for: hotkeyManager.selectedHotkey1,
                        customShortcut: currentShortcut
                    )
                    if !glyphs.isEmpty {
                        KeyCombo(keys: glyphs)
                    }
                }
            }

            if hotkeyManager.selectedHotkey2 != .none {
                SettingsRow(
                    iconSystemName: "2.circle",
                    label: "Shortcut 2",
                    iconTint: Palette.accent
                ) {
                    HStack(spacing: 8) {
                        hotkeyModePicker(binding: $hotkeyManager.hotkeyMode2)
                        hotkeyPicker(binding: $hotkeyManager.selectedHotkey2)
                        if hotkeyManager.selectedHotkey2 == .custom {
                            KeyboardShortcuts.Recorder(for: .toggleMiniRecorder2) { shortcut in
                                currentShortcut2 = shortcut
                            }
                            .controlSize(.small)
                        }
                        let glyphs = keyComboGlyphs(
                            for: hotkeyManager.selectedHotkey2,
                            customShortcut: currentShortcut2
                        )
                        if !glyphs.isEmpty {
                            KeyCombo(keys: glyphs)
                        }
                        Button {
                            withAnimation { hotkeyManager.selectedHotkey2 = .none }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if hotkeyManager.selectedHotkey1 != .none && hotkeyManager.selectedHotkey2 == .none {
                Button("Add Second Shortcut") {
                    withAnimation { hotkeyManager.selectedHotkey2 = .rightOption }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Additional Shortcuts

    private var additionalShortcutsCard: some View {
        SettingsCard(
            iconSystemName: "keyboard",
            iconTint: Palette.accent,
            title: "Additional Shortcuts",
            subtitle: "Paste, retry, cancel, middle-click."
        ) {
            SettingsRow(
                iconSystemName: "doc.on.clipboard",
                label: "Paste Last Transcription (Original)",
                iconTint: Palette.accent
            ) {
                KeyboardShortcuts.Recorder(for: .pasteLastTranscription)
                    .controlSize(.small)
            }

            SettingsRow(
                iconSystemName: "wand.and.rays",
                label: "Paste Last Transcription (Enhanced)",
                iconTint: Palette.accent
            ) {
                KeyboardShortcuts.Recorder(for: .pasteLastEnhancement)
                    .controlSize(.small)
            }

            SettingsRow(
                iconSystemName: "arrow.clockwise",
                label: "Retry Last Transcription",
                iconTint: Palette.accent
            ) {
                KeyboardShortcuts.Recorder(for: .retryLastTranscription)
                    .controlSize(.small)
            }

            // Custom Cancel - hierarchical
            ExpandableSettingsRow(
                isExpanded: $isCustomCancelExpanded,
                isEnabled: $isCustomCancelEnabled,
                label: "Custom Cancel Shortcut"
            ) {
                SettingsRow(
                    iconSystemName: "xmark.circle",
                    label: "Shortcut",
                    iconTint: Palette.accent
                ) {
                    KeyboardShortcuts.Recorder(for: .cancelRecorder)
                        .controlSize(.small)
                }
            }
            .onChange(of: isCustomCancelEnabled) { _, newValue in
                if !newValue {
                    KeyboardShortcuts.setShortcut(nil, for: .cancelRecorder)
                    isCustomCancelExpanded = false
                }
            }

            // Middle-Click
            ExpandableSettingsRow(
                isExpanded: $isMiddleClickExpanded,
                isEnabled: $hotkeyManager.isMiddleClickToggleEnabled,
                label: "Middle-Click Recording"
            ) {
                SettingsRow(
                    iconSystemName: "timer",
                    label: "Activation Delay",
                    iconTint: Palette.accent
                ) {
                    HStack {
                        TextField("", value: $hotkeyManager.middleClickActivationDelay, formatter: {
                            let formatter = NumberFormatter()
                            formatter.minimum = 0
                            return formatter
                        }())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("ms")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Recording Feedback

    private var recordingFeedbackCard: some View {
        SettingsCard(
            iconSystemName: "waveform",
            iconTint: Palette.accent,
            title: "Recording Feedback",
            subtitle: "Sound, mute, clipboard restore."
        ) {
            ExpandableSettingsRow(
                isExpanded: $isSoundFeedbackExpanded,
                isEnabled: $soundManager.isEnabled,
                label: "Sound Feedback"
            ) {
                CustomSoundSettingsView()
            }

            ExpandableSettingsRow(
                isExpanded: $isMuteSystemExpanded,
                isEnabled: $mediaController.isSystemMuteEnabled,
                label: "Mute Audio While Recording"
            ) {
                Picker("Resume Delay", selection: $mediaController.audioResumptionDelay) {
                    Text("0s").tag(0.0)
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("3s").tag(3.0)
                    Text("4s").tag(4.0)
                    Text("5s").tag(5.0)
                }
            }

            ExpandableSettingsRow(
                isExpanded: $isRestoreClipboardExpanded,
                isEnabled: $restoreClipboardAfterPaste,
                label: "Restore Clipboard After Paste"
            ) {
                Picker("Restore Delay", selection: $clipboardRestoreDelay) {
                    Text("250ms").tag(0.25)
                    Text("500ms").tag(0.5)
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("3s").tag(3.0)
                    Text("4s").tag(4.0)
                    Text("5s").tag(5.0)
                }
            }

            SettingsRow(
                iconSystemName: "terminal.fill",
                label: "Use AppleScript Paste",
                subtitle: "Enable if pasting fails on alternative layouts (e.g. Neo2). Uses AppleScript instead of simulated key events.",
                iconTint: Palette.accent
            ) {
                Toggle("", isOn: $useAppleScriptPaste)
                    .labelsHidden()
            }

            SettingsRow(
                iconSystemName: "exclamationmark.triangle",
                label: "Failure Dwell",
                subtitle: "How long the recorder shows a failure before retracting. Until-dismissed keeps the menubar dot until you open Settings or the next recording succeeds.",
                iconTint: Palette.accent
            ) {
                Picker("", selection: $failedDwellSeconds) {
                    Text("3 seconds").tag(3.0)
                    Text("6 seconds").tag(6.0)
                    Text("Until dismissed").tag(Double.infinity)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    // MARK: - Interface

    private var interfaceCard: some View {
        SettingsCard(
            iconSystemName: "rectangle.on.rectangle",
            iconTint: Palette.accent,
            title: "Interface",
            subtitle: "Where the Halo recorder appears."
        ) {
            RecorderStylePicker(selection: $recorderUIManager.recorderType)
        }
    }

    // MARK: - General

    private var generalCard: some View {
        SettingsCard(
            iconSystemName: "gearshape.fill",
            iconTint: Palette.neutral,
            title: "General",
            subtitle: "App behavior, dock, updates."
        ) {
            SettingsRow(
                iconSystemName: "dock.rectangle",
                label: "Hide Dock Icon",
                iconTint: Palette.neutral
            ) {
                Toggle("", isOn: $menuBarManager.isMenuBarOnly)
                    .labelsHidden()
            }

            SettingsRow(
                iconSystemName: "power",
                label: "Launch at Login",
                iconTint: Palette.neutral
            ) {
                LaunchAtLogin.Toggle("")
                    .labelsHidden()
            }

            SettingsRow(
                iconSystemName: "arrow.down.circle",
                label: "Auto-check Updates",
                iconTint: Palette.neutral
            ) {
                Toggle("", isOn: $autoUpdateCheck)
                    .labelsHidden()
                    .onChange(of: autoUpdateCheck) { _, newValue in
                        updaterViewModel.toggleAutoUpdates(newValue)
                    }
            }

            SettingsRow(
                iconSystemName: "megaphone.fill",
                label: "Show Announcements",
                iconTint: Palette.neutral
            ) {
                Toggle("", isOn: $enableAnnouncements)
                    .labelsHidden()
                    .onChange(of: enableAnnouncements) { _, newValue in
                        if newValue {
                            AnnouncementsService.shared.start()
                        } else {
                            AnnouncementsService.shared.stop()
                        }
                    }
            }

            HStack(spacing: 8) {
                Button("Check for Updates") {
                    updaterViewModel.checkForUpdates()
                }
                .disabled(!updaterViewModel.canCheckForUpdates)

                Spacer()
            }
        }
    }

    // MARK: - Privacy

    private var privacyCard: some View {
        SettingsCard(
            iconSystemName: "lock.fill",
            iconTint: Palette.success,
            title: "Privacy",
            subtitle: "Local-first by default. Audio stays on this Mac."
        ) {
            AudioCleanupSettingsView()

            Text("Control how VoiceInk handles your transcription data and audio recordings.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    // MARK: - Backup

    private var backupCard: some View {
        SettingsCard(
            iconSystemName: "tray.and.arrow.up",
            iconTint: Palette.neutral,
            title: "Backup",
            subtitle: "Export or import everything."
        ) {
            SettingsRow(
                iconSystemName: "square.and.arrow.up",
                label: "Export Settings",
                iconTint: Palette.neutral
            ) {
                Button("Export") {
                    ImportExportService.shared.exportSettings(
                        enhancementService: enhancementService,
                        whisperPrompt: WhisperPrompt(),
                        hotkeyManager: hotkeyManager,
                        menuBarManager: menuBarManager,
                        mediaController: mediaController,
                        playbackController: playbackController,
                        soundManager: soundManager,
                        recorderUIManager: recorderUIManager,
                        modelContext: modelContext
                    )
                }
            }

            SettingsRow(
                iconSystemName: "square.and.arrow.down",
                label: "Import Settings",
                iconTint: Palette.neutral
            ) {
                Button("Import") {
                    ImportExportService.shared.importSettings(
                        enhancementService: enhancementService,
                        whisperPrompt: WhisperPrompt(),
                        hotkeyManager: hotkeyManager,
                        menuBarManager: menuBarManager,
                        mediaController: mediaController,
                        playbackController: playbackController,
                        soundManager: soundManager,
                        recorderUIManager: recorderUIManager,
                        modelContext: modelContext,
                        transcriptionModelManager: transcriptionModelManager
                    )
                }
            }

            Text("Export or import all your settings, prompts, power modes, dictionary, and custom models.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsCard: some View {
        SettingsCard(
            iconSystemName: "stethoscope",
            iconTint: Palette.warn,
            title: "Diagnostics",
            subtitle: "Logs and crash reports."
        ) {
            DiagnosticsSettingsView()
        }
    }

    // MARK: - KeyCombo glyph derivation (P2.E)
    //
    // Maps the active `HotkeyOption` (single-modifier toggle) or a recorded
    // custom `KeyboardShortcuts.Shortcut` to an array of Unicode glyph
    // strings consumable by `KeyCombo` per spec §3.3.
    //
    // Single-modifier options collapse to one glyph (e.g. `.rightOption` →
    // ["⌥"]). `.custom` parses the package's `Shortcut.modifiers` (control,
    // option, shift, command in Apple's canonical glyph order) plus the key
    // portion stripped from `Shortcut.description` (last leg after the
    // modifier symbols — handles multi-char keys like "Space" cleanly).

    private func keyComboGlyphs(
        for option: HotkeyManager.HotkeyOption,
        customShortcut: KeyboardShortcuts.Shortcut?
    ) -> [String] {
        switch option {
        case .none:
            return []
        case .custom:
            guard let s = customShortcut else { return [] }
            var caps: [String] = []
            let m = s.modifiers
            if m.contains(.control) { caps.append("⌃") }
            if m.contains(.option)  { caps.append("⌥") }
            if m.contains(.shift)   { caps.append("⇧") }
            if m.contains(.command) { caps.append("⌘") }
            // Strip leading modifier glyphs from `description` to isolate the
            // key portion. Multi-char keys ("Space", "Tab") survive intact.
            let modifierGlyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
            let keyPart = String(s.description.drop(while: { modifierGlyphs.contains($0) }))
            if !keyPart.isEmpty {
                caps.append(keyPart)
            }
            return caps
        case .rightOption, .leftOption:    return ["⌥"]
        case .leftControl, .rightControl:  return ["⌃"]
        case .fn:                          return ["fn"]
        case .rightCommand:                return ["⌘"]
        case .rightShift:                  return ["⇧"]
        }
    }

    @ViewBuilder
    private func hotkeyPicker(binding: Binding<HotkeyManager.HotkeyOption>) -> some View {
        Picker("", selection: binding) {
            ForEach(HotkeyManager.HotkeyOption.allCases, id: \.self) { option in
                Text(option.displayName).tag(option)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private func hotkeyModePicker(binding: Binding<HotkeyManager.HotkeyMode>) -> some View {
        Picker("", selection: binding) {
            ForEach(HotkeyManager.HotkeyMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

// MARK: - Expandable Settings Row (entire row clickable)

struct ExpandableSettingsRow<Content: View>: View {
    @Binding var isExpanded: Bool
    @Binding var isEnabled: Bool
    let label: String
    var infoMessage: String? = nil
    var infoURL: String? = nil
    @ViewBuilder let content: () -> Content

    @State private var isHandlingToggleChange = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row - entire area is tappable
            HStack {
                Toggle(isOn: $isEnabled) {
                    HStack(spacing: 4) {
                        Text(label)
                        if let message = infoMessage {
                            if let url = infoURL {
                                InfoTip(message, learnMoreURL: url)
                            } else {
                                InfoTip(message)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isEnabled && isExpanded ? 90 : 0))
                    .opacity(isEnabled ? 1 : 0.4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isHandlingToggleChange else { return }
                if isEnabled {
                    withAnimation(Animation.haloPhaseCrossfade) {
                        isExpanded.toggle()
                    }
                }
            }

            // Expanded content with proper spacing
            if isEnabled && isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.top, 12)
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Animation.haloPhaseCrossfade, value: isExpanded)
        .onChange(of: isEnabled) { _, newValue in
            isHandlingToggleChange = true
            if newValue {
                withAnimation(Animation.haloPhaseCrossfade) {
                    isExpanded = true
                }
            } else {
                isExpanded = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isHandlingToggleChange = false
            }
        }
    }
}

// MARK: - Power Mode Section

struct PowerModeSection: View {
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @AppStorage("powerModeUIFlag") private var powerModeUIFlag = false
    @AppStorage(PowerModeDefaults.autoRestoreKey) private var powerModeAutoRestoreEnabled = false
    @State private var showDisableAlert = false
    @State private var isExpanded = false

    var body: some View {
        SettingsCard(
            iconSystemName: "bolt.fill",
            iconTint: Palette.warn,
            title: "Power Mode",
            subtitle: "App- and site-aware behavior.",
            statusText: powerModeManager.enabledConfigurations.isEmpty
                ? "Disabled"
                : "\(powerModeManager.enabledConfigurations.count) active",
            statusTone: powerModeManager.enabledConfigurations.isEmpty ? .neutral : .positive
        ) {
            ExpandableSettingsRow(
                isExpanded: $isExpanded,
                isEnabled: toggleBinding,
                label: "Power Mode",
                infoMessage: "Apply custom settings based on active app or website.",
                infoURL: "https://tryvoiceink.com/docs/power-mode"
            ) {
                Toggle(isOn: $powerModeAutoRestoreEnabled) {
                    HStack(spacing: 4) {
                        Text("Auto-Restore Preferences")
                        InfoTip("After each recording session, revert preferences to what was configured before Power Mode was activated.")
                    }
                }
            }
        }
        .alert("Power Mode Still Active", isPresented: $showDisableAlert) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("Disable or remove your Power Modes first.")
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { powerModeUIFlag },
            set: { newValue in
                if newValue {
                    powerModeUIFlag = true
                } else if powerModeManager.configurations.allSatisfy({ !$0.isEnabled }) {
                    powerModeUIFlag = false
                } else {
                    showDisableAlert = true
                }
            }
        )
    }
}

// MARK: - Experimental Section

struct ExperimentalSection: View {
    @ObservedObject private var playbackController = PlaybackController.shared
    @ObservedObject private var mediaController = MediaController.shared
    @State private var isPauseMediaExpanded = false

    var body: some View {
        SettingsCard(
            iconSystemName: "testtube.2",
            iconTint: Palette.neutral,
            title: "Experimental",
            subtitle: "Opt-in features still being tuned."
        ) {
            ExpandableSettingsRow(
                isExpanded: $isPauseMediaExpanded,
                isEnabled: $playbackController.isPauseMediaEnabled,
                label: "Pause Media While Recording",
                infoMessage: "Pauses playing media when recording starts and resumes when done."
            ) {
                Picker("Resume Delay", selection: $mediaController.audioResumptionDelay) {
                    Text("0s").tag(0.0)
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("3s").tag(3.0)
                    Text("4s").tag(4.0)
                    Text("5s").tag(5.0)
                }
            }
        }
    }
}

// MARK: - Text Extension

extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Power Mode Defaults

enum PowerModeDefaults {
    static let autoRestoreKey = "powerModeAutoRestoreEnabled"
}
