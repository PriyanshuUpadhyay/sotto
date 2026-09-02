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
    // "Every destination is reachable in one window from ONE flat sidebar."
    //
    // The body switches over a `@State` selection through an EXHAUSTIVE
    // `view(for:)` switch (no default) keyed on `SottoWindowTab`. Every
    // destination therefore has to be wired, and `renderedTabs == allCases`, so
    // no surface can be dropped from the sidebar without removing its enum case
    // — a compile error in the exhaustive switch, which these tests also catch.

    func test_renderedTabs_isExactlyAllCases() {
        XCTAssertEqual(
            SottoWindowView.renderedTabs,
            SottoWindowTab.allCases,
            "body must render every tab via the renderedTabs source"
        )
    }

    func test_allRequiredTabsPresent() {
        let cases = Set(SottoWindowTab.allCases)
        let required: Set<SottoWindowTab> = [
            .history, .dictionary, .models, .general, .shortcuts, .advanced,
        ]
        XCTAssertEqual(
            cases, required,
            "SottoWindow sidebar must expose History + Dictionary + the four settings rows; diff: \(cases.symmetricDifference(required))"
        )
    }

    /// There is no second navigation layer: the former Settings rail's pages are
    /// sidebar rows, so no row is titled "Settings".
    func test_sidebar_hasNoSettingsRow() {
        XCTAssertFalse(
            SottoWindowTab.allCases.contains { $0.title == "Settings" },
            "Settings must be a group header, not a selectable destination"
        )
    }

    /// The SETTINGS group is exactly the four rows under the header; History and
    /// Dictionary stack above it.
    func test_settingsGroup_isTheFourSettingsRows() {
        XCTAssertEqual(
            SottoWindowTab.allCases.filter(\.isSettingsGroup),
            [.models, .general, .shortcuts, .advanced]
        )
        XCTAssertEqual(
            SottoWindowTab.allCases.filter { !$0.isSettingsGroup },
            [.history, .dictionary]
        )
    }

    /// Dictionary is a first-class sidebar destination (design-mockups/02): its
    /// ONE home — the only place the vocabulary editors render.
    func test_dictionaryTab_isPresentWithTitle() {
        XCTAssertTrue(SottoWindowTab.allCases.contains(.dictionary))
        XCTAssertEqual(SottoWindowTab.dictionary.title, "Dictionary")
    }

    func test_dictionaryDestination_bodyRendersVocabularyTab() {
        let bodyType = String(describing: type(of: DictionaryDestinationView().body))
        XCTAssertTrue(bodyType.contains("VocabularyTab"),
                      "Dictionary destination must render the existing VocabularyTab; body was \(bodyType)")
    }

    /// Each settings row renders its EXISTING tab view under the shared pinned
    /// title, so every destination states where you are.
    func test_settingsRowDestinations_composeTitleOverTheirExistingTab() {
        let cases: [(String, String)] = [
            (String(describing: type(of: GeneralDestinationView().body)), "GeneralTab"),
            (String(describing: type(of: ShortcutsDestinationView().body)), "ShortcutsTab"),
            (String(describing: type(of: AdvancedDestinationView().body)), "AdvancedTab"),
            (String(describing: type(of: ModelsDestinationView().body)), "ModelsTab"),
        ]
        for (bodyType, tab) in cases {
            XCTAssertTrue(bodyType.contains("DestinationHeader"),
                          "\(tab)'s destination must carry the shared title header; body was \(bodyType)")
            XCTAssertTrue(bodyType.contains(tab),
                          "destination must render the existing \(tab); body was \(bodyType)")
        }
    }

    // MARK: - Routing: a Settings key targets a sidebar row
    //
    // `SettingsTab` survives as the routing key (deep links, the search index,
    // the section-jump notifications), but nothing renders it as a second
    // layer — every key maps to exactly one sidebar row.

    func test_everySettingsTab_mapsToASidebarRow() {
        let expected: [SettingsTab: SottoWindowTab] = [
            .general: .general,
            .shortcuts: .shortcuts,
            .models: .models,
            .vocabulary: .dictionary,
            .advanced: .advanced,
        ]
        for tab in SettingsTab.allCases {
            XCTAssertEqual(SottoWindowTab(settingsTab: tab), expected[tab],
                           "\(tab) must target its sidebar row")
        }
    }

    /// The reverse mapping is consistent: every row that answers to a routing
    /// key maps back to itself.
    func test_sidebarRow_settingsTab_roundTrips() {
        for row in SottoWindowTab.allCases {
            guard let key = row.settingsTab else {
                XCTAssertEqual(row, .history, "only History has no Settings routing key")
                continue
            }
            XCTAssertEqual(SottoWindowTab(settingsTab: key), row)
        }
    }

    /// Opening `.selectSettingsTab(.shortcuts)` selects the Shortcuts sidebar
    /// row: the coordinator stages that row and posts the notification the
    /// mounted window reads.
    func test_openSettingsTab_shortcuts_targetsShortcutsSidebarRow() {
        let coordinator = SottoWindowCoordinator.shared
        coordinator.pendingTab = nil
        coordinator.pendingSettingsTarget = nil
        coordinator.registerOpener { _ in }

        var posted: SettingsTab?
        let token = NotificationCenter.default.addObserver(
            forName: .selectSettingsTab, object: nil, queue: nil
        ) { note in posted = SottoWindowView.resolvedTab(from: note) }
        defer { NotificationCenter.default.removeObserver(token) }

        coordinator.open(settingsTab: .shortcuts)

        XCTAssertEqual(coordinator.pendingTab, .shortcuts)
        XCTAssertEqual(coordinator.pendingSettingsTarget, .tab(.shortcuts))
        XCTAssertEqual(posted, .shortcuts)
        XCTAssertEqual(posted.map(SottoWindowTab.init(settingsTab:)), .shortcuts)
    }

    /// A search hit on a dictionary section selects Dictionary and jumps:
    /// `open(settingsSection:)` stages the label AND opens the Dictionary row,
    /// so the jump is not lost when the notification fires before it mounts.
    func test_openSettingsSection_dictionary_selectsDictionaryRow_andStagesJump() {
        let coordinator = SottoWindowCoordinator.shared
        coordinator.pendingTab = nil
        coordinator.pendingSettingsTarget = nil
        coordinator.registerOpener { _ in }

        coordinator.open(settingsSection: .vocabulary, label: "Word Replacements")

        XCTAssertEqual(coordinator.pendingTab, .dictionary)
        XCTAssertEqual(coordinator.pendingSettingsTarget,
                       .section(tab: .vocabulary, label: "Word Replacements"))

        // Navigating to a different row invalidates it — it must not fire on a
        // later manual visit to Dictionary.
        coordinator.open(tab: .history, activate: false)
        XCTAssertNil(coordinator.pendingSettingsTarget)
    }

    /// Re-opening the SAME row keeps the staged jump — only navigating away
    /// drops it.
    func test_stagedTarget_survivesOpeningItsOwnRow() {
        let coordinator = SottoWindowCoordinator.shared
        coordinator.pendingTab = nil
        coordinator.pendingSettingsTarget = nil
        coordinator.registerOpener { _ in }

        coordinator.open(settingsSection: .advanced, label: "Backup & Restore")
        coordinator.open(tab: .advanced, activate: false)

        XCTAssertEqual(coordinator.pendingSettingsTarget,
                       .section(tab: .advanced, label: "Backup & Restore"))
    }

    // MARK: - Behavioral: resolvedTab is what .onReceive reads

    func test_resolvedTab_returnsTabFromUserInfo() {
        for tab in SettingsTab.allCases {
            let note = Notification(name: .selectSettingsTab, object: nil, userInfo: ["tab": tab])
            XCTAssertEqual(
                SottoWindowView.resolvedTab(from: note), tab,
                "resolvedTab must map userInfo[\"tab\"] to the SettingsTab so .selectSettingsTab selects its row."
            )
        }
    }

    func test_resolvedTab_returnsNilWhenUserInfoMissing() {
        let note = Notification(name: .selectSettingsTab, object: nil, userInfo: nil)
        XCTAssertNil(
            SottoWindowView.resolvedTab(from: note),
            "resolvedTab must return nil when no tab is supplied so selection is left unchanged."
        )
    }

    func test_resolvedTab_returnsNilWhenUserInfoWrongType() {
        let note = Notification(name: .selectSettingsTab, object: nil, userInfo: ["tab": "models"])
        XCTAssertNil(
            SottoWindowView.resolvedTab(from: note),
            "resolvedTab must return nil when userInfo[\"tab\"] is not a SettingsTab so selection is left unchanged."
        )
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
