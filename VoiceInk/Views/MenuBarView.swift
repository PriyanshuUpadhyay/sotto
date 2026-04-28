import SwiftUI
import SwiftData
import AppKit

// MARK: - MenuBarView
//
// Traditional NSMenu-style dropdown for the status item. Hosted via
// `MenuBarExtra(...) { MenuBarView() }.menuBarExtraStyle(.menu)` in
// `VoiceInk.swift`. SwiftUI projects each top-level child onto an NSMenuItem:
//   • `Button` → menu item
//   • `Toggle` → checkable item
//   • `Menu`   → submenu
//   • `Divider`→ separator
//
// Container views (HStack, VStack, custom backgrounds, glass materials) do
// NOT render as menu chrome under `.menu` style — keep this body strictly
// flat or it goes back to looking empty.

struct MenuBarView: View {
    @EnvironmentObject var engine: VoiceInkEngine
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService

    @Query(
        sort: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
    ) private var transcriptions: [Transcription]

    private static let recentLimit = 3

    var body: some View {
        Group {
            recordingButton

            Button("Show History…") {
                menuBarManager.openHistoryWindow()
            }

            Button("Open Main Window…") {
                menuBarManager.openMainWindowAndNavigate(to: "Main")
            }

            Divider()

            Toggle("AI Enhancement", isOn: $enhancementService.isEnhancementEnabled)

            promptMenu

            Divider()

            // Info-only rows. Disabled buttons render dimmed but stay readable —
            // SwiftUI's `.menu` style ignores `Text(...)` at the top level.
            Button(transcriptionRow) {}.disabled(true)
            Button(providerRow) {}.disabled(true)

            recentSection

            Divider()

            Button("Settings…") {
                menuBarManager.openMainWindowAndNavigate(to: "Settings")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit VoiceInk") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - Items

    @ViewBuilder
    private var recordingButton: some View {
        switch engine.recordingState {
        case .recording:
            Button("Stop Recording") {
                Task { await engine.toggleRecord() }
            }
        case .idle:
            Button("Start Recording") {
                Task { await engine.toggleRecord() }
            }
        default:
            Button("Working…") {}.disabled(true)
        }
    }

    @ViewBuilder
    private var promptMenu: some View {
        let prompts = enhancementService.allPrompts
        let activeId = enhancementService.selectedPromptId
        let activeTitle = prompts.first { $0.id == activeId }?.title ?? "None"
        Menu("Prompt: \(activeTitle)") {
            ForEach(prompts, id: \.id) { prompt in
                Button(prompt.title) {
                    enhancementService.setActivePrompt(prompt)
                }
            }
        }
        .disabled(!enhancementService.isEnhancementEnabled || prompts.isEmpty)
    }

    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(transcriptions.prefix(Self.recentLimit))
        if !recent.isEmpty {
            Divider()
            // SwiftUI doesn't expose a "section header" primitive in `.menu`
            // style, so the heading is just a disabled item — same vibe as
            // macOS's "Recent Documents" rows.
            Button("Recent") {}.disabled(true)
            ForEach(recent, id: \.id) { t in
                let preview = previewText(for: t)
                Button(preview) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(t.enhancedText ?? t.text, forType: .string)
                }
            }
        }
    }

    // MARK: - Display helpers

    private var transcriptionRow: String {
        let model = transcriptionModelManager.currentTranscriptionModel?.displayName ?? "None"
        return "Transcription: \(model)"
    }

    private var providerRow: String {
        let provider = aiService.selectedProvider.rawValue
        let connected = aiService.isAPIKeyValid ? "" : "  (not configured)"
        return "Enhancement: \(provider)\(connected)"
    }

    private func previewText(for t: Transcription) -> String {
        let raw = (t.enhancedText?.isEmpty == false ? t.enhancedText : t.text) ?? ""
        let single = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = single.trimmingCharacters(in: .whitespaces)
        if trimmed.count > 60 {
            return "“\(trimmed.prefix(60))…”"
        }
        return "“\(trimmed)”"
    }
}
