import SwiftUI
import KeyboardShortcuts

struct ShortcutsTab: View {
    @EnvironmentObject private var hotkeyManager: HotkeyManager

    @State private var currentShortcut = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)
    @State private var isCustomCancelEnabled = KeyboardShortcuts.getShortcut(for: .cancelRecorder) != nil
    @State private var isCustomCancelExpanded = false
    /// The cancel binding the user last had, so turning Custom Cancel back on
    /// restores it instead of losing it.
    @State private var lastCancelShortcut = KeyboardShortcuts.getShortcut(for: .cancelRecorder)
    /// Raw names of the shortcuts that currently have a binding. Held in state
    /// so recording one updates the card's badge immediately — a bare
    /// `KeyboardShortcuts.getShortcut` call in `body` publishes nothing.
    @State private var boundNames: Set<String> = Self.currentlyBoundNames()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightedSection: ShortcutsTabSection?

    // MARK: - Introspectable composition descriptor
    //
    // Every control on the Shortcuts tab is enumerated here, together with the
    // EXISTING KeyboardShortcuts.Name / manager surface it binds
    // to. The body renders `ForEach(renderedSections)` — and `renderedSections
    // == allCases` — through the EXHAUSTIVE `view(for:)` switch. So the rendered
    // composition IS this descriptor by construction: a section cannot be
    // dropped from the body without removing its enum case (a compile error in
    // the exhaustive switch), and a shortcut Name cannot be renamed without
    // failing `SettingsShortcutsTabTests`.

    enum ShortcutsTabSection: CaseIterable, Hashable {
        case primaryShortcuts
        case paste
        case retry
        case commandPalette
        case customCancel
    }

    struct ShortcutBinding {
        let section: ShortcutsTabSection
        /// The exact, existing `KeyboardShortcuts.Name` raw string this section's
        /// recorder binds to.
        let name: String
    }

    /// Each shortcut-recorder section mapped to its exact existing
    /// `KeyboardShortcuts.Name`.
    static let shortcutBindings: [ShortcutBinding] = [
        .init(section: .primaryShortcuts,  name: KeyboardShortcuts.Name.toggleMiniRecorder.rawValue),
        .init(section: .paste,             name: KeyboardShortcuts.Name.pasteLastEnhancement.rawValue),
        .init(section: .retry,             name: KeyboardShortcuts.Name.retryLastTranscription.rawValue),
        .init(section: .commandPalette,    name: KeyboardShortcuts.Name.commandPalette.rawValue),
        .init(section: .customCancel,      name: KeyboardShortcuts.Name.cancelRecorder.rawValue),
    ]

    /// The exact, ordered list the body's `ForEach` renders from. It IS
    /// `allCases`, so the rendered set equals the full descriptor by
    /// construction; `SettingsShortcutsTabTests` asserts this equality.
    static var renderedSections: [ShortcutsTabSection] { ShortcutsTabSection.allCases }

    /// The raw names that hold a binding right now — the initial value of
    /// `boundNames`, read once at mount.
    private static func currentlyBoundNames() -> Set<String> {
        Set(shortcutBindings.compactMap { binding in
            let name = KeyboardShortcuts.Name(binding.name)
            return KeyboardShortcuts.getShortcut(for: name) == nil ? nil : binding.name
        })
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Self.renderedSections, id: \.self) { section in
                        view(for: section)
                            .id(section)
                            .settingsSectionHighlight(active: highlightedSection == section, reduceMotion: reduceMotion)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas)
            .tint(Brand.tint)
            .onReceive(NotificationCenter.default.publisher(for: .selectSettingsSection)) { note in
                handleSettingsSectionJump(note, thisTab: .shortcuts, sections: Self.renderedSections, label: { $0.searchLabel }, proxy: proxy, reduceMotion: reduceMotion, highlight: $highlightedSection)
            }
        }
    }

    // MARK: - Descriptor-driven rendering
    //
    // Exhaustive over ShortcutsTabSection: removing an enum case fails to
    // compile, so the descriptor cannot drift from what the body renders. Each
    // case binds to the EXISTING KeyboardShortcuts.Name / manager surface it
    // owned before the migration.

    @ViewBuilder
    private func view(for section: ShortcutsTabSection) -> some View {
        switch section {
        case .primaryShortcuts:
            SettingsCard(
                iconSystemName: "command",
                iconTint: Brand.tint,
                title: "Shortcuts",
                subtitle: "Trigger recording from anywhere.",
                statusText: hotkeyManager.selectedHotkey1 == .none ? "None" : "1 active",
                statusTone: hotkeyManager.selectedHotkey1 == .none ? .warning : .neutral
            ) {
                SettingsRow(
                    iconSystemName: "1.circle",
                    label: "Shortcut 1",
                    iconTint: Brand.tint
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
                    }
                }
            }

        case .paste:
            recorderCard(
                icon: "doc.on.clipboard",
                title: "Paste Last Transcription",
                subtitle: "Paste your last transcription at the cursor.",
                name: .pasteLastEnhancement
            )

        case .retry:
            recorderCard(
                icon: "arrow.clockwise",
                title: "Retry Last Transcription",
                subtitle: "Re-run the last transcription.",
                name: .retryLastTranscription
            )

        case .commandPalette:
            recorderCard(
                icon: "command",
                title: "Command Palette (global)",
                subtitle: "Summon the ⌘K command palette from any app.",
                name: .commandPalette
            )

        case .customCancel:
            SettingsCard(
                iconSystemName: "xmark.circle",
                iconTint: Brand.tint,
                title: "Custom Cancel",
                subtitle: "Bind a dedicated cancel shortcut."
            ) {
                ExpandableSettingsRow(
                    isExpanded: $isCustomCancelExpanded,
                    isEnabled: $isCustomCancelEnabled,
                    label: "Custom Cancel Shortcut"
                ) {
                    SettingsRow(
                        iconSystemName: "xmark.circle",
                        label: "Shortcut",
                        iconTint: Brand.tint
                    ) {
                        KeyboardShortcuts.Recorder(for: .cancelRecorder) { shortcut in
                            lastCancelShortcut = shortcut ?? lastCancelShortcut
                            setBound(.cancelRecorder, shortcut != nil)
                        }
                        .controlSize(.small)
                    }
                }
                .onChange(of: isCustomCancelEnabled) { _, newValue in
                    if newValue {
                        if let saved = lastCancelShortcut {
                            KeyboardShortcuts.setShortcut(saved, for: .cancelRecorder)
                            setBound(.cancelRecorder, true)
                        }
                    } else {
                        lastCancelShortcut = KeyboardShortcuts.getShortcut(for: .cancelRecorder) ?? lastCancelShortcut
                        KeyboardShortcuts.setShortcut(nil, for: .cancelRecorder)
                        setBound(.cancelRecorder, false)
                        isCustomCancelExpanded = false
                    }
                }
            }
        }
    }

    private func recorderCard(
        icon: String,
        title: String,
        subtitle: String,
        name: KeyboardShortcuts.Name
    ) -> some View {
        SettingsCard(
            iconSystemName: "keyboard",
            iconTint: Brand.tint,
            title: title,
            subtitle: subtitle,
            statusText: boundNames.contains(name.rawValue) ? "Bound" : nil,
            statusTone: .neutral
        ) {
            SettingsRow(
                iconSystemName: icon,
                label: title,
                iconTint: Brand.tint
            ) {
                KeyboardShortcuts.Recorder(for: name) { shortcut in
                    setBound(name, shortcut != nil)
                }
                .controlSize(.small)
            }
        }
    }

    /// Keeps the "Bound" badge in step with what the recorder just captured.
    private func setBound(_ name: KeyboardShortcuts.Name, _ isBound: Bool) {
        if isBound {
            boundNames.insert(name.rawValue)
        } else {
            boundNames.remove(name.rawValue)
        }
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
}
