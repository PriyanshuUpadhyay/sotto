import XCTest
@testable import Sotto

final class CommandPaletteTests: XCTestCase {

    // MARK: - Task 1: focusTranscription notification

    func test_focusTranscription_notificationName_exists() {
        XCTAssertEqual(Notification.Name.focusTranscription.rawValue, "focusTranscription")
    }

    // MARK: - Task 2: PaletteFuzzy

    func test_fuzzy_emptyQuery_scoresZero() {
        XCTAssertEqual(PaletteFuzzy.score("", "Paste last"), 0)
    }

    func test_fuzzy_exactMatch_outranks_prefix_outranks_contains() {
        let exact = PaletteFuzzy.score("paste", "paste")!
        let prefix = PaletteFuzzy.score("paste", "paste last")!
        let contains = PaletteFuzzy.score("last", "paste last")!
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, contains)
    }

    func test_fuzzy_subsequence_matches_lowest() {
        // "pl" is a subsequence of "Paste Last" but not a contiguous substring.
        let sub = PaletteFuzzy.score("pl", "Paste Last")
        XCTAssertNotNil(sub)
        XCTAssertLessThan(sub!, PaletteFuzzy.score("paste", "paste last")!)
    }

    func test_fuzzy_noMatch_returnsNil() {
        XCTAssertNil(PaletteFuzzy.score("zzz", "Paste last"))
    }

    // MARK: - Task 3: PaletteCommand

    func test_paletteCommand_run_invokesClosure() {
        var ran = false
        let cmd = PaletteCommand(
            id: "x", title: "T", subtitle: "S",
            systemImage: "bolt", category: .quickAction,
            requiresFocusRestore: false, run: { ran = true }
        )
        cmd.run()
        XCTAssertTrue(ran)
        XCTAssertEqual(cmd.category.label, "Action")
    }

    // MARK: - Task 4: CommandRegistry builders

    func test_navigationCommands_oneRowPerIndexEntry() {
        let cmds = CommandRegistry.navigationCommands(index: SettingsSearch.index)
        XCTAssertEqual(cmds.count, SettingsSearch.index.count)
        XCTAssertTrue(cmds.allSatisfy { $0.category == .navigate })
    }

    func test_navigationCommand_run_postsSelectSettingsSection() {
        let entry = SettingsSearch.index.first!
        let cmds = CommandRegistry.navigationCommands(index: [entry])
        let exp = expectation(forNotification: .selectSettingsSection, object: nil) { note in
            (note.userInfo?["label"] as? String) == entry.label
        }
        cmds[0].run()
        wait(for: [exp], timeout: 1)
    }

    func test_modelCommands_oneRowPerModel_runSetsActive() {
        var setName: String?
        let cmds = CommandRegistry.modelCommands(
            modelNames: ["Parakeet v3", "Whisper Turbo"],
            activeName: "Parakeet v3",
            setActive: { setName = $0 }
        )
        XCTAssertEqual(cmds.count, 2)
        // Active model's subtitle marks it active.
        XCTAssertTrue(cmds[0].subtitle.lowercased().contains("active"))
        cmds[1].run()
        XCTAssertEqual(setName, "Whisper Turbo")
    }

    func test_transcriptCommands_carryPasteItem_andFocusRestore() {
        let id = UUID()
        let cmds = CommandRegistry.transcriptCommands(
            rows: [(id: id, raw: "raw text", enhanced: "enhanced text", preview: "raw text")]
        )
        XCTAssertEqual(cmds.count, 1)
        XCTAssertEqual(cmds[0].category, .transcript)
        // Transcript rows paste into the captured app, so they must restore focus.
        XCTAssertTrue(cmds[0].requiresFocusRestore)
        XCTAssertEqual(cmds[0].transcript?.raw, "raw text")
        XCTAssertEqual(cmds[0].transcript?.enhanced, "enhanced text")
    }

    // MARK: - Task 4b: transcript paste decision (Enter = enhanced, ⌘Enter = raw)

    func test_transcriptUseEnhanced_plainEnter_true_commandHeld_false() {
        XCTAssertTrue(CommandRegistry.transcriptUseEnhanced(commandHeld: false))   // plain ⏎ → enhanced
        XCTAssertFalse(CommandRegistry.transcriptUseEnhanced(commandHeld: true))   // ⌘⏎ → raw
    }

    func test_transcriptPasteText_enhancedWhenPresentAndRequested() {
        let item = TranscriptPasteItem(raw: "RAW", enhanced: "ENH")
        XCTAssertEqual(CommandRegistry.transcriptPasteText(item: item, useEnhanced: true), "ENH")
        XCTAssertEqual(CommandRegistry.transcriptPasteText(item: item, useEnhanced: false), "RAW")
    }

    func test_transcriptPasteText_fallsBackToRaw_whenEnhancedMissingOrBlank() {
        let none = TranscriptPasteItem(raw: "RAW", enhanced: nil)
        XCTAssertEqual(CommandRegistry.transcriptPasteText(item: none, useEnhanced: true), "RAW")
        let blank = TranscriptPasteItem(raw: "RAW", enhanced: "   \n ")
        XCTAssertEqual(CommandRegistry.transcriptPasteText(item: blank, useEnhanced: true), "RAW")
    }

    // MARK: - Task 5: quick actions

    func test_quickActionCommands_threeActions_focusRestoreTrue() {
        let cmds = CommandRegistry.quickActionCommands(
            pasteLast: {}, pasteLastEnhancement: {}, retryLast: {}
        )
        XCTAssertEqual(cmds.count, 3)
        XCTAssertTrue(cmds.allSatisfy { $0.requiresFocusRestore })
        XCTAssertTrue(cmds.allSatisfy { $0.category == .quickAction })
        XCTAssertTrue(cmds.contains { $0.title.localizedCaseInsensitiveContains("retry") })
    }

    // MARK: - Task 6: CommandPaletteModel ranking

    @MainActor
    func test_model_emptyQuery_keepsProviderOrder() {
        let cmds = CommandRegistry.quickActionCommands(pasteLast: {}, pasteLastEnhancement: {}, retryLast: {})
        let model = CommandPaletteModel()
        model.setSource(cmds)
        model.applyQuery("")
        XCTAssertEqual(model.results.map { $0.id }, cmds.map { $0.id })
        XCTAssertEqual(model.selectionIndex, 0)
    }

    @MainActor
    func test_model_query_ranksTitleMatchesFirst_and_dropsNonMatches() {
        let source = [
            PaletteCommand(id: "a", title: "Paste last transcription", subtitle: "Action",
                           systemImage: "x", category: .quickAction, requiresFocusRestore: true, run: {}),
            PaletteCommand(id: "b", title: "Retry last transcription", subtitle: "Action",
                           systemImage: "x", category: .quickAction, requiresFocusRestore: true, run: {}),
        ]
        let model = CommandPaletteModel()
        model.setSource(source)
        model.applyQuery("paste")
        XCTAssertEqual(model.results.map { $0.id }, ["a"])
    }

    @MainActor
    func test_model_moveSelection_clampsToBounds() {
        let source = [
            PaletteCommand(id: "a", title: "Alpha", subtitle: "", systemImage: "x",
                           category: .navigate, requiresFocusRestore: false, run: {}),
            PaletteCommand(id: "b", title: "Beta", subtitle: "", systemImage: "x",
                           category: .navigate, requiresFocusRestore: false, run: {}),
        ]
        let model = CommandPaletteModel()
        model.setSource(source)
        model.applyQuery("")
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectionIndex, 0)        // clamps at top
        model.moveSelection(by: 5)
        XCTAssertEqual(model.selectionIndex, 1)        // clamps at bottom
    }
}
