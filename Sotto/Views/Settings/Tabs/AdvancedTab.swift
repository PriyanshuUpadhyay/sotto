import SwiftUI

struct AdvancedTab: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @ObservedObject private var soundManager = SoundManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var playbackController = PlaybackController.shared

    // Read-only mirror of the cleanup gates owned by AudioCleanupSettingsView,
    // surfaced in the privacy card's status badge. Same keys.
    @AppStorage("IsTranscriptionCleanupEnabled") private var isTranscriptCleanupForBadge = false
    @AppStorage("IsAudioCleanupEnabled") private var isAudioCleanupForBadge = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightedSection: AdvancedTabSection?

    // MARK: - Introspectable composition descriptor
    //
    // Every Advanced surface is enumerated here. The body renders
    // `ForEach(renderedSections)` — and `renderedSections == allCases` —
    // through the EXHAUSTIVE `view(for:)` switch, so the rendered composition
    // IS this descriptor by construction: a section cannot be dropped from the
    // body without removing its enum case (a compile error in the exhaustive
    // switch). `SettingsAdvancedTabTests` asserts this equality.

    enum AdvancedTabSection: CaseIterable, Hashable {
        case privacy
        case backup
    }

    /// The exact, ordered list the body's `ForEach` renders from. It IS
    /// `allCases`, so the rendered set equals the full descriptor by
    /// construction.
    static var renderedSections: [AdvancedTabSection] { AdvancedTabSection.allCases }

    /// The backup section reuses `ImportExportService.shared` export/import.
    static let backupUsesImportExportService = true

    // MARK: - Factories for the reused existing views

    static func privacyView() -> AudioCleanupSettingsView { AudioCleanupSettingsView() }

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
                handleSettingsSectionJump(note, thisTab: .advanced, sections: Self.renderedSections, label: { $0.searchLabel }, proxy: proxy, reduceMotion: reduceMotion, highlight: $highlightedSection)
            }
        }
    }

    // MARK: - Descriptor-driven rendering
    //
    // Exhaustive over AdvancedTabSection: removing an enum case fails to
    // compile, so the descriptor cannot drift from what the body renders. Each
    // case reuses the EXISTING view/manager it owned before the migration.

    @ViewBuilder
    private func view(for section: AdvancedTabSection) -> some View {
        switch section {
        case .privacy:
            let cleanupBadge = isTranscriptCleanupForBadge || isAudioCleanupForBadge
            SettingsCard(
                iconSystemName: "lock.fill",
                iconTint: Palette.success,
                title: "Privacy",
                subtitle: "Local-first by default. Audio stays on this Mac.",
                statusText: cleanupBadge ? "Auto-cleanup on" : "Default",
                statusTone: cleanupBadge ? .positive : .neutral
            ) {
                Self.privacyView()

                Text("Control how Sotto handles your transcription data and audio recordings.")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

        case .backup:
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
                            modelContext: modelContext,
                            transcriptionModelManager: transcriptionModelManager
                        )
                    }
                }

                Text("Export or import all your settings, prompts, dictionary, and custom models.")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }
}
