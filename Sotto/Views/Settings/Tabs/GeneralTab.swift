import SwiftUI
import LaunchAtLogin
import AVFoundation

struct GeneralTab: View {
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @ObservedObject private var soundManager = SoundManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @StateObject private var permissions = PermissionManager()

    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    @AppStorage(SottoFeedback.hapticsEnabledKey) private var hapticsEnabled = true

    @State private var isMuteSystemExpanded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightedSection: GeneralTabSection?

    // MARK: - Introspectable composition descriptor
    //
    // Every control migrated into the General tab is enumerated here, together
    // with the EXISTING persisted key / manager it binds to. The body renders
    // `ForEach(renderedSections)` — and `renderedSections == allCases` — through
    // the EXHAUSTIVE `view(for:)` switch. So the rendered composition IS this
    // descriptor by construction: a section cannot be dropped from the body
    // without removing its enum case (a compile error in the exhaustive switch),
    // and a key cannot be renamed without failing `SettingsGeneralTabTests`.

    enum GeneralTabSection: CaseIterable, Hashable {
        case audioInput
        case soundFeedback
        case launchAtLogin
        case hideDock
        case autoUpdate
        case checkForUpdates
        case permissionsStatus
    }

    struct MigratedBinding {
        let section: GeneralTabSection
        /// The existing @AppStorage key / UserDefaults key / manager identifier.
        let settingsKey: String
    }

    /// Each migrated control mapped to its existing persisted key / manager.
    /// `checkForUpdates` (action) and `permissionsStatus` (read-only) own no
    /// persisted setting, so they are not listed here.
    static let migratedBindings: [MigratedBinding] = [
        .init(section: .audioInput,         settingsKey: "audioInputMode"),          // AudioDeviceManager
        .init(section: .soundFeedback,      settingsKey: "isSoundFeedbackEnabled"),  // SoundManager.isEnabled
        .init(section: .soundFeedback,      settingsKey: "isSystemMuteEnabled"),     // MediaController.isSystemMuteEnabled
        .init(section: .hideDock,           settingsKey: "IsMenuBarOnly"),           // MenuBarManager.isMenuBarOnly
        .init(section: .launchAtLogin,      settingsKey: "LaunchAtLogin"),           // LaunchAtLogin library
        .init(section: .autoUpdate,         settingsKey: "autoUpdateCheck"),         // @AppStorage
    ]

    /// The exact, ordered list the body's `ForEach` renders from. It IS
    /// `allCases`, so the rendered set equals the full descriptor by
    /// construction — adding/removing a case automatically changes what is
    /// rendered, and `SettingsGeneralTabTests` asserts this equality.
    static var renderedSections: [GeneralTabSection] { GeneralTabSection.allCases }

    /// Factory for the audio-input section so its reuse of the full
    /// `AudioInputSettingsView` (all three modes + device picker + prioritized
    /// add/remove/reorder + refresh/current-device state) is introspectable.
    static func audioInputView() -> AudioInputSettingsView {
        AudioInputSettingsView()
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
                handleSettingsSectionJump(note, thisTab: .general, sections: Self.renderedSections, label: { $0.searchLabel }, proxy: proxy, reduceMotion: reduceMotion, highlight: $highlightedSection)
            }
        }
    }

    // MARK: - Descriptor-driven rendering
    //
    // Exhaustive over GeneralTabSection: removing an enum case fails to compile,
    // so the descriptor cannot drift from what the body actually renders. Each
    // case binds to the EXISTING manager / @AppStorage key it owned before the
    // migration.

    @ViewBuilder
    private func view(for section: GeneralTabSection) -> some View {
        switch section {
        case .audioInput:
            SettingsCard(
                iconSystemName: "waveform",
                iconTint: Brand.tint,
                title: "Audio Input",
                subtitle: "Input mode, device selection, priority order."
            ) {
                Self.audioInputView()
                    .frame(minHeight: 420)
            }

        case .soundFeedback:
            SettingsCard(
                iconSystemName: "speaker.wave.2.fill",
                iconTint: Brand.tint,
                title: "Recording Feedback",
                subtitle: "Cue sounds and mute-while-recording."
            ) {
                SettingsRow(
                    iconSystemName: "speaker.wave.2.fill",
                    label: "Sound Feedback",
                    subtitle: "Play cue sounds on start, completion, and failure.",
                    iconTint: Brand.tint
                ) {
                    Toggle("", isOn: $soundManager.isEnabled)
                        .labelsHidden()
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
                SettingsRow(
                    iconSystemName: "hand.tap.fill",
                    label: "Haptic Feedback",
                    subtitle: "Tactile taps on arm, commit, and failure (Force Touch trackpads).",
                    iconTint: Brand.tint
                ) {
                    Toggle("", isOn: $hapticsEnabled)
                        .labelsHidden()
                }
            }

        case .launchAtLogin:
            SettingsCard(
                iconSystemName: "power",
                iconTint: Palette.neutral,
                title: "Launch at Login",
                subtitle: "Start Sotto automatically when you sign in."
            ) {
                SettingsRow(
                    iconSystemName: "power",
                    label: "Launch at Login",
                    iconTint: Palette.neutral
                ) {
                    LaunchAtLogin.Toggle("")
                        .labelsHidden()
                }
            }

        case .hideDock:
            SettingsCard(
                iconSystemName: "dock.rectangle",
                iconTint: Palette.neutral,
                title: "Dock",
                subtitle: "Run from the menu bar only."
            ) {
                SettingsRow(
                    iconSystemName: "dock.rectangle",
                    label: "Hide Dock Icon",
                    iconTint: Palette.neutral
                ) {
                    Toggle("", isOn: $menuBarManager.isMenuBarOnly)
                        .labelsHidden()
                }
            }

        case .autoUpdate:
            SettingsCard(
                iconSystemName: "arrow.down.circle",
                iconTint: Palette.neutral,
                title: "Updates",
                subtitle: "Keep Sotto up to date."
            ) {
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
            }

        case .checkForUpdates:
            SettingsCard(
                iconSystemName: "arrow.triangle.2.circlepath",
                iconTint: Palette.neutral,
                title: "Check for Updates",
                subtitle: "Look for a new version now."
            ) {
                HStack(spacing: 8) {
                    Button("Check for Updates") {
                        updaterViewModel.checkForUpdates()
                    }
                    .disabled(!updaterViewModel.canCheckForUpdates)

                    Spacer()
                }
            }

        case .permissionsStatus:
            PermissionsStatusStrip(source: permissions)
        }
    }
}
