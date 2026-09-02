import XCTest
import SwiftUI
@testable import Sotto

@MainActor
final class SettingsWindowTests: XCTestCase {

    func test_settingsWindow_isConstructible() {
        _ = SettingsWindow()
    }

    func test_settingsWindow_conformsToView() {
        XCTAssertTrue((SettingsWindow() as Any) is any View)
    }

    func test_settingsTabs_areExactlyTheFiveSurfaces() {
        XCTAssertEqual(
            Set(SettingsTab.allCases),
            [.general, .shortcuts, .models, .vocabulary, .advanced]
        )
    }

    /// ⌘, / the Settings menu item is a shortcut to the main window's General
    /// row — the Settings scene hosts no surface of its own any more.
    func test_settingsScene_forwardsToTheGeneralSidebarRow() {
        let coordinator = SottoWindowCoordinator.shared
        coordinator.pendingTab = nil
        coordinator.pendingSettingsTarget = nil
        coordinator.registerOpener { _ in }

        SettingsWindow.openMainWindowOnGeneral()

        XCTAssertEqual(coordinator.pendingTab, .general)
    }

    // MARK: - Crash regression guard
    //
    // The Settings sidebar previously used `.searchable(placement: .sidebar)`.
    // On first render its NSSearchField re-entered SwiftUI layout invalidation
    // during AppKit's cursor-rect display cycle, throwing an uncaught NSException
    // that whisper.framework's global terminate handler turned into an abort —
    // a hard crash the moment Settings opened. The fix removes the search field.
    // This guard fails if a search field is reintroduced into a settings surface
    // or into the window sidebar that now carries the search box.
    //
    // It is a SOURCE scan because the failure is a display-cycle/run-loop crash
    // that cannot be reproduced in a headless unit test.

    private func surfaceSource(_ relativePath: String, from filePath: String = #filePath) throws -> String {
        let url = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()   // SottoTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func sottoWindowSource(from filePath: String = #filePath) throws -> String {
        try surfaceSource("Sotto/Views/SottoWindow/SottoWindowView.swift", from: filePath)
    }

    func test_settingsSurfaces_haveNoSearchableSearchField() throws {
        for source in [
            try surfaceSource("Sotto/Views/Settings/SettingsWindow.swift"),
            try sottoWindowSource(),
        ] {
            XCTAssertFalse(
                source.contains(".searchable"),
                "The settings surfaces must not use `.searchable` — its NSSearchField re-enters layout during the AppKit display cycle and aborts the app."
            )
        }
    }

    /// The window hosts its destinations in the hand-built flat sidebar
    /// (`SottoSidebarRow` + an exhaustive content switch). The hard safety rule
    /// is unchanged: NSView-backed controls (KeyboardShortcuts.Recorder,
    /// NSSearchField) re-enter layout fatally inside a NavigationSplitView, so
    /// the container must NOT be one.
    func test_window_usesCustomSidebarNotNavigationSplitView() throws {
        let source = try sottoWindowSource()
        XCTAssertTrue(
            source.contains("SottoSidebarRow"),
            "SottoWindowView must host its destinations in the custom flat sidebar (SottoSidebarRow)."
        )
        XCTAssertFalse(
            source.contains("NavigationSplitView"),
            "SottoWindowView must not use NavigationSplitView — NSView-backed controls (KeyboardShortcuts.Recorder, NSSearchField) re-enter layout and abort the app inside it."
        )
    }

    /// There is exactly ONE navigation layer: no Settings rail survives.
    func test_noSecondNavigationLayer() throws {
        let source = try sottoWindowSource()
        XCTAssertFalse(source.contains("SettingsRailRow"),
                       "The Settings rail is gone — its pages are sidebar rows.")
        XCTAssertTrue(source.contains("GeneralTab"), "The sidebar must host GeneralTab.")
        XCTAssertTrue(source.contains("ShortcutsTab"), "The sidebar must host ShortcutsTab.")
        XCTAssertTrue(source.contains("AdvancedTab"), "The sidebar must host AdvancedTab.")
        XCTAssertTrue(source.contains("ModelsTab"), "The sidebar must host ModelsTab.")
        XCTAssertTrue(source.contains("VocabularyTab"), "The sidebar must host VocabularyTab.")
    }
}
