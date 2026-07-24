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
        let required: Set<SottoWindowTab> = [.history, .models, .settings]
        XCTAssertEqual(
            cases, required,
            "SottoWindow sidebar must expose History + Models + Settings; diff: \(cases.symmetricDifference(required))"
        )
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
