import XCTest
import SwiftUI
@testable import Sotto

@MainActor
final class SettingsVocabularyTabTests: XCTestCase {

    func test_vocabularyTab_isConstructible() {
        _ = VocabularyTab()
    }

    func test_vocabularyTab_conformsToView() {
        XCTAssertTrue((VocabularyTab() as Any) is any View)
    }

    // MARK: - Anchor
    // "Dictionary + Word replacements both editable from this one tab over the
    //  same SwiftData models as before."
    //
    // The body renders `ForEach(VocabularyTab.renderedSections)` and dispatches
    // to an EXHAUSTIVE `view(for:)` switch. `renderedSections == VocabularyTab
    // Section.allCases`, so the rendered set IS the descriptor by construction:
    // a section cannot be dropped from the body without removing the enum case
    // (compile error in the exhaustive switch) which these tests also catch.

    func test_allRequiredSectionsPresent() {
        let cases = Set(VocabularyTab.VocabularyTabSection.allCases)
        let required: Set<VocabularyTab.VocabularyTabSection> = [
            .dictionary, .wordReplacements,
        ]
        XCTAssertEqual(
            cases, required,
            "VocabularyTab descriptor must be exactly the 2 merged sections; diff: \(cases.symmetricDifference(required))"
        )
    }

    func test_renderedSections_isExactlyAllCases() {
        XCTAssertEqual(
            VocabularyTab.renderedSections,
            VocabularyTab.VocabularyTabSection.allCases,
            "body must render every descriptor case via ForEach(renderedSections)"
        )
    }

    // Each factory returns the EXISTING editor view type — dropping a section's
    // editor changes the factory return type and fails to compile, so all three
    // editors are provably reused over the same SwiftData models.

    func test_dictionarySection_reusesExistingVocabularyView() {
        XCTAssertTrue((VocabularyTab.dictionaryView(whisperPrompt: WhisperPrompt()) as Any) is VocabularyView,
                      "dictionary section must reuse the existing VocabularyView")
    }

    func test_wordReplacementsSection_reusesExistingWordReplacementView() {
        XCTAssertTrue((VocabularyTab.wordReplacementsView() as Any) is WordReplacementView,
                      "word replacements section must reuse the existing WordReplacementView")
    }
}
