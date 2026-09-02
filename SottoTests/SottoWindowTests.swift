import XCTest
import SwiftUI
@testable import Sotto

@MainActor
final class SottoWindowTests: XCTestCase {

    func test_sottoWindowView_isConstructible() {
        _ = SottoWindowView()
    }

    func test_sottoWindowView_conformsToView() {
        XCTAssertTrue((SottoWindowView() as Any) is any View)
    }

    // MARK: - Anchor
    // "History and Settings are both reachable in one window via a toggle; the
    //  window is not always-open."
    //
    // The body switches over a `@State` selection through an EXHAUSTIVE
    // `view(for:)` switch (no default) keyed on `SottoWindowTab`. Both tabs
    // therefore have to be wired, and `renderedTabs == allCases`, so neither
    // surface can be dropped from the toggle without removing its enum case —
    // a compile error in the exhaustive switch, which these tests also catch.

    func test_renderedTabs_isExactlyAllCases() {
        XCTAssertEqual(
            SottoWindowView.renderedTabs,
            SottoWindowTab.allCases,
            "body must render every tab via the renderedTabs source"
        )
    }

    func test_allRequiredTabsPresent() {
        let cases = Set(SottoWindowTab.allCases)
        let required: Set<SottoWindowTab> = [.history, .models, .dictionary, .settings]
        XCTAssertEqual(
            cases, required,
            "SottoWindow sidebar must expose History + Models + Dictionary + Settings; diff: \(cases.symmetricDifference(required))"
        )
    }

    /// Dictionary is a first-class sidebar destination (design-mockups/02): its
    /// ONE home. The rail row under Settings is gone, so this is the only place
    /// the vocabulary editors render.
    func test_dictionaryTab_isPresentWithTitle() {
        XCTAssertTrue(SottoWindowTab.allCases.contains(.dictionary))
        XCTAssertEqual(SottoWindowTab.dictionary.title, "Dictionary")
    }

    func test_dictionaryDestination_bodyRendersVocabularyTab() {
        let bodyType = String(describing: type(of: DictionaryDestinationView().body))
        XCTAssertTrue(bodyType.contains("VocabularyTab"),
                      "Dictionary destination must render the existing VocabularyTab; body was \(bodyType)")
    }

    /// Settings is the destination that used to state nowhere it was: it now
    /// carries the same pinned title its siblings have, over SettingsContentView.
    func test_settingsDestination_bodyComposesTitleOverSettingsContent() {
        let bodyType = String(describing: type(of: SettingsDestinationView().body))
        XCTAssertTrue(bodyType.contains("DestinationHeader"),
                      "Settings destination must carry the shared title header; body was \(bodyType)")
        XCTAssertTrue(bodyType.contains("SettingsContentView"),
                      "Settings destination must render SettingsContentView; body was \(bodyType)")
    }

    /// A staged dictionary section survives a closed window: `open(dictionarySection:)`
    /// stages the label AND opens the Dictionary destination, so the jump is not
    /// lost when the notification fires before the destination mounts.
    func test_openDictionarySection_stagesLabel_andOpensDictionaryTab() {
        let coordinator = SottoWindowCoordinator.shared
        coordinator.pendingTab = nil
        coordinator.pendingDictionarySection = nil
        coordinator.registerOpener { _ in }

        coordinator.open(dictionarySection: "Word Replacements")

        XCTAssertEqual(coordinator.pendingTab, .dictionary)
        XCTAssertEqual(coordinator.pendingDictionarySection, "Word Replacements")

        // Navigating elsewhere invalidates it — it must not fire on a later
        // manual visit to Dictionary.
        coordinator.open(tab: .history, activate: false)
        XCTAssertNil(coordinator.pendingDictionarySection)
    }

    /// Settings is the in-window third segment: the enum carries a `.settings`
    /// case titled "Settings", rendered inline via `view(for:)` (SettingsContentView).
    func test_settingsTab_isPresentWithTitle() {
        XCTAssertTrue(SottoWindowTab.allCases.contains(.settings))
        XCTAssertEqual(SottoWindowTab.settings.title, "Settings")
    }

    /// The History destination is the composition the window actually renders
    /// (`content(for: .history)` returns `Self.historyView()`): the today-scoped
    /// HistoryStatsBand stacked over the EXISTING InlineHistoryView
    /// (design-mockups/02). This pins the factory to that type; the body test
    /// below enforces the composition itself. Stats math is covered by
    /// HistoryStats' own tests.
    func test_historyFactory_returnsHistoryDestinationView() {
        XCTAssertTrue((SottoWindowView.historyView() as Any) is HistoryDestinationView)
    }

    /// Enforce the composition: the concrete body type (VStack<TupleView<...>>)
    /// carries its child view types, so dropping the band or the history list
    /// from the destination fails here.
    func test_historyDestination_bodyComposesBandOverInlineHistory() {
        let bodyType = String(describing: type(of: HistoryDestinationView().body))
        XCTAssertTrue(bodyType.contains("HistoryStatsBand"),
                      "History destination must render the today stats band; body was \(bodyType)")
        XCTAssertTrue(bodyType.contains("InlineHistoryView"),
                      "History destination must render the existing InlineHistoryView; body was \(bodyType)")
    }

    /// The Settings factory renders SettingsContentView — proving `view(for: .settings)`
    /// resolves to the in-window Settings surface. Dropping it = compile error.
    func test_settingsFactory_returnsSettingsContentView() {
        XCTAssertTrue((SottoWindowView.settingsView() as Any) is SettingsContentView)
    }

    // MARK: - On-demand opener
    // The window is opened on demand via a single stable WindowGroup id, and a
    // requested tab is staged for the window to read when it appears. This is
    // the seam History routing + "Open Sotto…" both drive.

    func test_coordinator_windowID_isStable() {
        XCTAssertEqual(SottoWindowCoordinator.windowID, "sotto-main")
    }

    func test_open_stagesTab_andInvokesOpenerWithWindowID() {
        let coordinator = SottoWindowCoordinator.shared
        coordinator.pendingTab = nil
        var openedID: String?
        coordinator.registerOpener { openedID = $0 }

        // activate:false keeps the unit test from touching activation policy /
        // stealing foreground focus during the headless test run.
        coordinator.open(tab: .history, activate: false)

        XCTAssertEqual(openedID, SottoWindowCoordinator.windowID)
        XCTAssertEqual(coordinator.pendingTab, .history)
    }
}
