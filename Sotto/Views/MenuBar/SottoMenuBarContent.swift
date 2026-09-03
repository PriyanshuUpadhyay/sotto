import SwiftUI
import SwiftData
import AppKit

// MARK: - SottoMenuBarContent
//
// Supersedes MenuBarView as the status-item dropdown content. Hosted under
// `MenuBarExtra { ... }.menuBarExtraStyle(.menu)`, so the body must stay flat:
// SwiftUI projects each top-level child onto an NSMenuItem (Button → item,
// Menu → submenu, Divider → separator). Container views render as nothing
// under `.menu` style.

struct SottoMenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var engine: SottoEngine
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var updaterViewModel: UpdaterViewModel

    @Query(
        sort: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
    ) private var transcriptions: [Transcription]

    var body: some View {
        Group {
            Button(statusHeader) {}.disabled(true)

            Divider()

            dictationButton

            recentSection

            Divider()

            Button("Open Sotto") {
                NSApplication.shared.setActivationPolicy(.regular)
                openWindow(id: SottoWindowCoordinator.windowID)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Button("Settings…") {
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": "Settings"]
                )
            }
            .keyboardShortcut(",", modifiers: .command)

            // The app menu's copy of this item is only visible while a Sotto
            // window is in front; the dropdown is where a menu-bar-only user
            // actually looks.
            Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
                .disabled(!updaterViewModel.canCheckForUpdates)

            Divider()

            Button("Quit Sotto") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - Items

    @ViewBuilder
    private var dictationButton: some View {
        switch engine.recordingState {
        case .recording:
            Button("Stop Dictation") {
                Task { await engine.toggleRecord() }
            }
        case .idle:
            Button("Start Dictation") {
                Task { await engine.toggleRecord() }
            }
        default:
            Button("Working…") {}.disabled(true)
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let items = Self.recentItems(from: transcriptions)
        if !items.isEmpty {
            Divider()
            Button("Recent") {}.disabled(true)
            ForEach(items) { item in
                // Each recent item is a submenu (Menu → NSMenu submenu under
                // `.menu` style) so the silent copy gains a labeled action plus
                // a jump-to-History action. The parent menu closes on any
                // click, so copy feedback must live OUTSIDE the menu — surfaced
                // via the existing AnnouncementManager reminder toast.
                Menu(item.preview) {
                    Button("Copy") { copyToClipboard(item.text) }
                    Button("Show in History") {
                        SottoWindowCoordinator.shared.open(tab: .history)
                    }
                }
            }
        }
    }

    /// Copies `text` and surfaces a brief "Copied to clipboard" confirmation
    /// via the existing `AnnouncementManager` reminder-toast panel (the menu
    /// has already closed by the time this runs, so an in-menu flash would be
    /// invisible).
    @MainActor
    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        AnnouncementManager.shared.showReminderToast(
            CopyConfirmationToastView(),
            reduceMotion: reduceMotion
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000) // 1.4s
            AnnouncementManager.shared.dismissReminderToast()
        }
    }

    private var statusHeader: String {
        let model = transcriptionModelManager.currentTranscriptionModel?.displayName
        return Self.statusText(state: engine.recordingState, modelDisplayName: model)
    }

    // MARK: - Pure helpers (unit-testable)

    struct RecentItem: Identifiable, Equatable {
        let id: UUID
        let text: String
        let preview: String
    }

    static func recentItems(from transcripts: [Transcription], limit: Int = 3) -> [RecentItem] {
        transcripts
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { t in
                let payload = (t.enhancedText?.isEmpty == false ? t.enhancedText : t.text) ?? t.text
                return RecentItem(id: t.id, text: payload, preview: previewText(payload))
            }
    }

    static func statusText(state: RecordingState, modelDisplayName: String?) -> String {
        let model = modelDisplayName ?? "None"
        return statusLabel(for: state) + " · \(model)"
    }

    /// Glanceable label per engine lifecycle state, so the header distinguishes
    /// recording from the transcribe/enhance tail (not just Recording/Ready).
    static func statusLabel(for state: RecordingState) -> String {
        switch state {
        case .idle:         return "Ready"
        case .starting:     return "Starting…"
        case .recording:    return "Recording"
        case .transcribing: return "Transcribing…"
        case .enhancing:    return "Enhancing…"
        case .busy:         return "Working…"
        }
    }

    static func previewText(_ raw: String) -> String {
        let single = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = single.trimmingCharacters(in: .whitespaces)
        if trimmed.count > 60 {
            return "“\(trimmed.prefix(60))…”"
        }
        return "“\(trimmed)”"
    }
}

// MARK: - CopyConfirmationToastView
//
// Transient confirmation surfaced through `AnnouncementManager.showReminderToast`
// after a Recent-item copy. Kept minimal — the toast panel/animation lifecycle
// is owned by AnnouncementManager; this is only its content.
private struct CopyConfirmationToastView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.brandAcid)
                .accessibilityHidden(true)

            Text("Copied to clipboard")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(Palette.inkPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 220, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}
