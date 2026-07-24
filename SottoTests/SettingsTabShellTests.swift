import XCTest
@testable import Sotto

final class SettingsTabShellTests: XCTestCase {
    func test_settingsTab_isExhaustive_fiveCases() {
        XCTAssertEqual(SettingsTab.allCases.count, 5)
    }

    func test_settingsTab_hasEveryConfigSection() {
        XCTAssertEqual(
            Set(SettingsTab.allCases),
            [.general, .shortcuts, .models, .vocabulary, .advanced]
        )
    }

    func test_settingsTab_identifiableByRawValue() {
        for tab in SettingsTab.allCases {
            XCTAssertEqual(tab.id, tab.rawValue)
        }
    }

    // Compile-level proof that SettingsWindow() is constructible with no args,
    // so it can serve as the content of the app's `Settings` scene (mounted in
    // Sotto.swift). The scene graph itself can't be introspected headlessly;
    // the gate-validator reads Sotto.swift to confirm the wiring.
    @MainActor
    func test_settingsWindow_isConstructible() {
        _ = SettingsWindow()
    }
}
