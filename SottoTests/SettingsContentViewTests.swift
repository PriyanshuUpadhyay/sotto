import XCTest
import SwiftUI
@testable import Sotto

@MainActor
final class SettingsContentViewTests: XCTestCase {

    func test_settingsContentView_isConstructible() {
        _ = SettingsContentView()
    }

    func test_settingsContentView_conformsToView() {
        XCTAssertTrue((SettingsContentView() as Any) is any View)
    }

    // MARK: - Source scan
    //
    // The Settings body is factored out of SettingsWindow into a reusable
    // SettingsContentView so it can render both in the native Settings scene and
    // inline in the main window. These source scans lock the structural intent:
    // a TabView container hosting all five SettingsTab surfaces, switched by the
    // .selectSettingsTab notification, and crucially NOT a NavigationSplitView
    // (NSView-backed controls re-enter layout and abort the app inside one).

    private func settingsContentViewSource(from filePath: String = #filePath) throws -> String {
        let url = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()   // SottoTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sotto/Views/Settings/SettingsContentView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func test_settingsContentView_usesCustomRailNotNavigationSplitView() throws {
        let source = try settingsContentViewSource()
        // W4 Bet C flattened the inner 5-tab TabView into a custom onyx rail
        // (SettingsRailRow + a detail switch). The hard safety rule survives:
        // the container must NOT be a NavigationSplitView — its NSView-backed
        // controls (KeyboardShortcuts.Recorder, NSSearchField) re-enter layout
        // and abort the app inside one.
        XCTAssertTrue(
            source.contains("SettingsRailRow"),
            "SettingsContentView must host its tabs in the custom onyx rail (SettingsRailRow)."
        )
        XCTAssertFalse(
            source.contains("NavigationSplitView"),
            "SettingsContentView must not use NavigationSplitView — NSView-backed controls (KeyboardShortcuts.Recorder, NSSearchField) re-enter layout and abort the app inside it."
        )
    }

    func test_settingsContentView_hostsRemainingFourSettingsTabs() throws {
        let source = try settingsContentViewSource()
        XCTAssertTrue(source.contains("GeneralTab"), "SettingsContentView must host GeneralTab.")
        XCTAssertTrue(source.contains("ShortcutsTab"), "SettingsContentView must host ShortcutsTab.")
        XCTAssertTrue(source.contains("VocabularyTab"), "SettingsContentView must host VocabularyTab.")
        XCTAssertTrue(source.contains("AdvancedTab"), "SettingsContentView must host AdvancedTab.")
        // Models lives in exactly one place — the window sidebar destination
        // (2026-07 revamp). Settings must NOT instantiate it.
        XCTAssertFalse(source.contains("ModelsTab()"), "SettingsContentView must not host ModelsTab — Models is a window-level destination.")
    }

    func test_settingsContentView_drivesRailFromFilteredTabs() throws {
        let source = try settingsContentViewSource()
        // The rail lists `SettingsSearch(query:).filteredTabs()` — derived from
        // SettingsTab.allCases — so an empty query surfaces all five tabs
        // (hostsAllFiveSettingsTabs guards that each surface is present).
        XCTAssertTrue(
            source.contains("filteredTabs"),
            "SettingsContentView's rail must drive its tabs from SettingsSearch.filteredTabs() (derived from SettingsTab.allCases)."
        )
    }

    func test_settingsContentView_subscribesToSelectSettingsTab() throws {
        let source = try settingsContentViewSource()
        XCTAssertTrue(
            source.contains(".selectSettingsTab"),
            "SettingsContentView must subscribe to .selectSettingsTab to switch the selected tab."
        )
    }

    // MARK: - Behavioral: selectSettingsTab → selected tab update

    func test_resolvedTab_returnsTabFromUserInfo() {
        for tab in SettingsTab.allCases {
            let note = Notification(name: .selectSettingsTab, object: nil, userInfo: ["tab": tab])
            XCTAssertEqual(
                SettingsContentView.resolvedTab(from: note), tab,
                "resolvedTab must map userInfo[\"tab\"] to the selected SettingsTab so .selectSettingsTab updates selection."
            )
        }
    }

    func test_resolvedTab_returnsNilWhenUserInfoMissing() {
        let note = Notification(name: .selectSettingsTab, object: nil, userInfo: nil)
        XCTAssertNil(
            SettingsContentView.resolvedTab(from: note),
            "resolvedTab must return nil when no tab is supplied so selection is left unchanged."
        )
    }

    func test_resolvedTab_returnsNilWhenUserInfoWrongType() {
        let note = Notification(name: .selectSettingsTab, object: nil, userInfo: ["tab": "models"])
        XCTAssertNil(
            SettingsContentView.resolvedTab(from: note),
            "resolvedTab must return nil when userInfo[\"tab\"] is not a SettingsTab so selection is left unchanged."
        )
    }

    // MARK: - Behavioral: the action reducer IS what .onReceive executes
    //
    // The .onReceive(.selectSettingsTab) closure switches on
    // `action(current:notification:)`: .select(tab) assigns the rail selection;
    // .openModelsWindowTab forwards to the window-level Models destination —
    // .models has no rail row here, so selecting it would render a hidden page.

    func test_action_modelsTab_remapsToWindowModelsDestination() {
        let note = Notification(name: .selectSettingsTab, object: nil, userInfo: ["tab": SettingsTab.models])
        XCTAssertEqual(
            SettingsContentView.action(current: .general, notification: note),
            .openModelsWindowTab,
            "A .selectSettingsTab(.models) notification must open the window-level Models destination, never a hidden Settings page."
        )
    }

    func test_action_nonModelsTabs_selectTheTab() {
        for tab in SettingsTab.allCases where tab != .models {
            let note = Notification(name: .selectSettingsTab, object: nil, userInfo: ["tab": tab])
            XCTAssertEqual(
                SettingsContentView.action(current: .general, notification: note),
                .select(tab),
                "Non-models tabs must select the rail row."
            )
        }
    }

    func test_action_noTab_keepsCurrentSelection() {
        let note = Notification(name: .selectSettingsTab, object: nil, userInfo: nil)
        XCTAssertEqual(
            SettingsContentView.action(current: .advanced, notification: note),
            .select(.advanced),
            "With no tab supplied the current selection must be kept."
        )
    }

    // nextSelection stays the inner reducer action() builds on.

    func test_nextSelection_switchesToTabFromUserInfo() {
        for tab in SettingsTab.allCases {
            let current = SettingsTab.allCases.first { $0 != tab } ?? tab
            let note = Notification(name: .selectSettingsTab, object: nil, userInfo: ["tab": tab])
            XCTAssertEqual(
                SettingsContentView.nextSelection(current: current, notification: note), tab,
                "nextSelection must switch selection to the SettingsTab carried in userInfo[\"tab\"]."
            )
        }
    }

    func test_nextSelection_keepsCurrentWhenNoTab() {
        for current in SettingsTab.allCases {
            let note = Notification(name: .selectSettingsTab, object: nil, userInfo: nil)
            XCTAssertEqual(
                SettingsContentView.nextSelection(current: current, notification: note), current,
                "nextSelection must keep the current selection when no tab is supplied."
            )
        }
    }

    func test_nextSelection_keepsCurrentWhenWrongType() {
        for current in SettingsTab.allCases {
            let note = Notification(name: .selectSettingsTab, object: nil, userInfo: ["tab": "models"])
            XCTAssertEqual(
                SettingsContentView.nextSelection(current: current, notification: note), current,
                "nextSelection must keep the current selection when userInfo[\"tab\"] is not a SettingsTab."
            )
        }
    }
}
