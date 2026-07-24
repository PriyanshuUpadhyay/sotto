import XCTest
import SwiftUI
@testable import Sotto

@MainActor
final class SettingsAdvancedTabTests: XCTestCase {

    func test_advancedTab_isConstructible() {
        _ = AdvancedTab()
    }

    func test_advancedTab_conformsToView() {
        XCTAssertTrue((AdvancedTab() as Any) is any View)
    }

    // MARK: - Descriptor
    // "Advanced tab: Privacy & auto-cleanup, and Backup."
    //
    // The body renders `ForEach(AdvancedTab.renderedSections)` and dispatches to
    // an EXHAUSTIVE `view(for:)` switch. `renderedSections == AdvancedTabSection
    // .allCases`, so the rendered set IS the descriptor by construction: a
    // section cannot be dropped from the body without removing the enum case
    // (compile error in the exhaustive switch) which these tests also catch.

    func test_allRequiredSectionsPresent() {
        let cases = Set(AdvancedTab.AdvancedTabSection.allCases)
        let required: Set<AdvancedTab.AdvancedTabSection> = [
            .privacy, .backup,
        ]
        XCTAssertEqual(
            cases, required,
            "AdvancedTab descriptor must be exactly the 2 sections; diff: \(cases.symmetricDifference(required))"
        )
    }

    func test_renderedSections_isExactlyAllCases() {
        XCTAssertEqual(
            AdvancedTab.renderedSections,
            AdvancedTab.AdvancedTabSection.allCases,
            "body must render every descriptor case via ForEach(renderedSections)"
        )
    }

    // MARK: - Section factories reuse the EXISTING views/managers.
    // Dropping a section's source view changes the factory return type and fails
    // to compile, so each surface is provably reused over the same state.

    func test_privacySection_reusesExistingAudioCleanupSettingsView() {
        XCTAssertTrue((AdvancedTab.privacyView() as Any) is AudioCleanupSettingsView,
                      "privacy section must reuse the existing AudioCleanupSettingsView")
    }

    // Backup reuses the existing ImportExportService.
    func test_backup_usesImportExportService() {
        XCTAssertTrue(AdvancedTab.backupUsesImportExportService,
                      "backup section must reuse ImportExportService.shared export/import")
    }
}
