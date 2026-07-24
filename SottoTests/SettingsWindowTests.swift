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

    // MARK: - Crash regression guard
    //
    // The Settings sidebar previously used `.searchable(placement: .sidebar)`.
    // On first render its NSSearchField re-entered SwiftUI layout invalidation
    // during AppKit's cursor-rect display cycle, throwing an uncaught NSException
    // that whisper.framework's global terminate handler turned into an abort —
    // a hard crash the moment Settings opened. The fix removes the search field.
    // This guard fails if a search field is reintroduced into SettingsWindow.
    //
    // It is a SOURCE scan because the failure is a display-cycle/run-loop crash
    // that cannot be reproduced in a headless unit test.

    private func settingsSurfaceSource(_ relativePath: String, from filePath: String = #filePath) throws -> String {
        let url = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()   // SottoTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func settingsWindowSource(from filePath: String = #filePath) throws -> String {
        try settingsSurfaceSource("Sotto/Views/Settings/SettingsWindow.swift", from: filePath)
    }

    private func settingsContentSource(from filePath: String = #filePath) throws -> String {
        try settingsSurfaceSource("Sotto/Views/Settings/SettingsContentView.swift", from: filePath)
    }

    func test_settingsWindow_hasNoSearchableSearchField() throws {
        // No `.searchable` anywhere in the Settings surface — neither the thin
        // SettingsWindow wrapper nor the SettingsContentView body that now hosts
        // the controls.
        for source in [try settingsWindowSource(), try settingsContentSource()] {
            XCTAssertFalse(
                source.contains(".searchable"),
                "The Settings surface must not use `.searchable` — its NSSearchField re-enters layout during the AppKit display cycle and aborts the app when Settings opens."
            )
        }
    }

    // SettingsWindow is a thin wrapper; the container lives in
    // SettingsContentView, which W4 Bet C flattened from a TabView into a custom
    // onyx rail (SettingsRailRow). The hard safety rule is unchanged: NSView-
    // backed controls (KeyboardShortcuts.Recorder, NSSearchField) re-enter layout
    // fatally inside a NavigationSplitView hosted in the Settings scene, so the
    // container must NOT be a NavigationSplitView.
    func test_settingsWindow_usesCustomRailNotNavigationSplitView() throws {
        let source = try settingsContentSource()
        XCTAssertTrue(
            source.contains("SettingsRailRow"),
            "SettingsContentView must host its tabs in the custom onyx rail (SettingsRailRow)."
        )
        XCTAssertFalse(
            source.contains("NavigationSplitView"),
            "SettingsContentView must not use NavigationSplitView — NSView-backed controls (KeyboardShortcuts.Recorder, NSSearchField) re-enter layout and abort the app inside it."
        )
    }
}
