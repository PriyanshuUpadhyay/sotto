import Foundation
import SwiftData

/// Assembles `[PaletteCommand]` from app surfaces. The static builders take
/// narrow inputs + callbacks so they unit-test without a live engine; the
/// `@MainActor all(engine:query:)` composer wires them to the running app.
enum CommandRegistry {

    // MARK: Pure builders

    static func navigationCommands(index: [SettingsSearchResult]) -> [PaletteCommand] {
        index.map { entry in
            PaletteCommand(
                id: "nav:\(entry.id)",
                title: entry.label,
                subtitle: "\(entry.tab.title) · Settings",
                systemImage: "arrow.right.circle",
                category: .navigate,
                requiresFocusRestore: false,
                run: {
                    // Staged + posted AFTER the window opens (the old
                    // post-then-open order was lossy pre-mount).
                    SottoWindowCoordinator.shared.open(settingsSection: entry.tab, label: entry.label)
                }
            )
        }
    }

    /// Dictionary navigation: one row per VocabularyTab section, opening the
    /// window's Dictionary destination (its one home) rather than a Settings
    /// rail row. Built from the section descriptor, so a section cannot be
    /// added or dropped without this list following it.
    static func dictionaryCommands(
        sections: [VocabularyTab.VocabularyTabSection] = VocabularyTab.VocabularyTabSection.allCases
    ) -> [PaletteCommand] {
        sections.map { section in
            PaletteCommand(
                id: "nav:dictionary:\(section.searchLabel)",
                title: section.searchLabel,
                subtitle: "Dictionary",
                systemImage: "arrow.right.circle",
                category: .navigate,
                requiresFocusRestore: false,
                run: {
                    SottoWindowCoordinator.shared.open(dictionarySection: section.searchLabel)
                }
            )
        }
    }

    static func modelCommands(modelNames: [String],
                              activeName: String?,
                              setActive: @escaping (String) -> Void) -> [PaletteCommand] {
        modelNames.map { name in
            let isActive = name == activeName
            return PaletteCommand(
                id: "model:\(name)",
                title: "Switch model: \(name)",
                subtitle: isActive ? "Active · model" : "model",
                systemImage: "waveform",
                category: .model,
                requiresFocusRestore: false,
                run: { setActive(name) }
            )
        }
    }

    static func transcriptCommands(
        rows: [(id: UUID, raw: String, enhanced: String?, preview: String)]
    ) -> [PaletteCommand] {
        rows.map { row in
            PaletteCommand(
                id: "transcript:\(row.id.uuidString)",
                title: row.preview,
                subtitle: "transcript",
                systemImage: "text.quote",
                category: .transcript,
                requiresFocusRestore: true,
                run: {},
                transcript: TranscriptPasteItem(raw: row.raw, enhanced: row.enhanced)
            )
        }
    }

    /// Modifier → which text to paste. Plain ⏎/click pastes the enhanced
    /// rewrite; holding ⌘ pastes the raw transcript instead.
    static func transcriptUseEnhanced(commandHeld: Bool) -> Bool { !commandHeld }

    /// Enhanced rewrite when present (non-blank) and requested, else the raw
    /// transcript. Pure so the paste decision is unit-testable without UI.
    static func transcriptPasteText(item: TranscriptPasteItem, useEnhanced: Bool) -> String {
        if useEnhanced,
           let enhanced = item.enhanced,
           !enhanced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return enhanced
        }
        return item.raw
    }

    static func quickActionCommands(pasteLast: @escaping () -> Void,
                                    pasteLastEnhancement: @escaping () -> Void,
                                    retryLast: @escaping () -> Void) -> [PaletteCommand] {
        [
            PaletteCommand(id: "action:pasteLast", title: "Paste last transcription",
                           subtitle: "Action", systemImage: "doc.on.clipboard",
                           category: .quickAction, requiresFocusRestore: true, run: pasteLast),
            PaletteCommand(id: "action:pasteLastEnhancement", title: "Paste last enhancement",
                           subtitle: "Action", systemImage: "sparkles",
                           category: .quickAction, requiresFocusRestore: true, run: pasteLastEnhancement),
            PaletteCommand(id: "action:retryLast", title: "Retry last transcription",
                           subtitle: "Action", systemImage: "arrow.clockwise",
                           category: .quickAction, requiresFocusRestore: true, run: retryLast),
        ]
    }

    // MARK: Live composer

    /// Assembles every command for the running app. `query` is used only to
    /// fetch matching transcripts (the rest are fuzzy-filtered downstream).
    @MainActor
    static func all(engine: SottoEngine, query: String) -> [PaletteCommand] {
        let ctx = engine.modelContext

        let quick = quickActionCommands(
            pasteLast: { LastTranscriptionService.pasteLastTranscription(from: ctx) },
            pasteLastEnhancement: { LastTranscriptionService.pasteLastEnhancement(from: ctx) },
            retryLast: {
                LastTranscriptionService.retryLastTranscription(
                    from: ctx,
                    transcriptionModelManager: engine.transcriptionModelManager,
                    serviceRegistry: engine.serviceRegistry,
                    enhancementService: engine.enhancementService
                )
            }
        )

        let models = modelCommands(
            modelNames: engine.transcriptionModelManager.allAvailableModels.map { $0.name },
            activeName: engine.transcriptionModelManager.currentTranscriptionModel?.name,
            setActive: { name in
                if let m = engine.transcriptionModelManager.allAvailableModels.first(where: { $0.name == name }) {
                    engine.transcriptionModelManager.setDefaultTranscriptionModel(m)
                }
            }
        )

        // Prompt switching was removed when enhancement collapsed to a single
        // fixed prompt, so the palette no longer offers prompt-switch commands.
        let nav = navigationCommands(index: SettingsSearch.index) + dictionaryCommands()

        let transcripts = transcriptCommands(
            rows: fetchTranscriptRows(from: ctx, matching: query, limit: 6)
        )

        return quick + transcripts + models + nav
    }

    @MainActor
    private static func fetchTranscriptRows(
        from ctx: ModelContext,
        matching query: String,
        limit: Int
    ) -> [(id: UUID, raw: String, enhanced: String?, preview: String)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if !trimmed.isEmpty {
            descriptor.predicate = #Predicate { $0.text.localizedStandardContains(trimmed) }
        }
        descriptor.fetchLimit = max(0, limit)
        let rows = (try? ctx.fetch(descriptor)) ?? []
        return rows.map { t in
            let preview = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (id: t.id,
                    raw: t.text,
                    enhanced: t.enhancedText,
                    preview: preview.isEmpty ? "(empty transcript)" : String(preview.prefix(80)))
        }
    }
}
