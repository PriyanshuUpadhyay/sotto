import XCTest
import SwiftUI
@testable import Sotto

/// Covers `features/filler_word_control.feature`.
///
/// The three scenarios are: the Vocabulary tab exposes both filler controls,
/// removal honours the on/off toggle, and a word taken off the list survives
/// even while removal is on.
@MainActor
final class FillerWordControlTests: XCTestCase {

    // MARK: - Filler Word Control 01 — the tab shows both controls

    func test_vocabularyTab_hasFillerWordsSection() {
        XCTAssertTrue(
            VocabularyTab.VocabularyTabSection.allCases.contains(.fillerWords),
            "Vocabulary tab must expose the filler word section"
        )
    }

    func test_fillerWordsSection_reusesExistingFillerWordsSettingsView() {
        XCTAssertTrue(
            (VocabularyTab.fillerWordsView() as Any) is FillerWordsSettingsView,
            "filler section must reuse the existing FillerWordsSettingsView, which owns both the toggle and the word list"
        )
    }

    func test_fillerWordsSection_isSearchable() {
        XCTAssertEqual(VocabularyTab.VocabularyTabSection.fillerWords.searchLabel, "Filler Words")
    }

    // MARK: - Filler Word Control 02 — removal honours the toggle

    func test_removalOn_omitsFillerWord() {
        let result = TranscriptionOutputFilter.removingFillerWords(
            "so um this is the plan",
            enabled: true,
            fillerWords: ["um"]
        )
        XCTAssertFalse(result.contains("um"), "removal on must omit the filler word; got \(result)")
    }

    func test_removalOff_keepsFillerWord() {
        let result = TranscriptionOutputFilter.removingFillerWords(
            "so um this is the plan",
            enabled: false,
            fillerWords: ["um"]
        )
        XCTAssertEqual(result, "so um this is the plan", "removal off must leave the transcript untouched")
    }

    // MARK: - Filler Word Control 03 — a word off the list survives

    func test_removalOn_keepsWordAbsentFromList() {
        for word in ["um", "basically"] {
            let listWithoutWord = FillerWordManager.defaultFillerWords.filter { $0 != word }
            let result = TranscriptionOutputFilter.removingFillerWords(
                "so \(word) this is the plan",
                enabled: true,
                fillerWords: listWithoutWord
            )
            XCTAssertTrue(
                result.contains(word),
                "\(word) is off the list, so removal must keep it; got \(result)"
            )
        }
    }

    // Guards the regex boundary: removing "um" must not eat "umbrella".
    func test_removal_matchesWholeWordsOnly() {
        let result = TranscriptionOutputFilter.removingFillerWords(
            "um the umbrella",
            enabled: true,
            fillerWords: ["um"]
        )
        XCTAssertTrue(result.contains("umbrella"), "whole-word match only; got \(result)")
    }

    // MARK: - List editing

    func test_removeWord_takesWordOffTheList() {
        let manager = makeManager(fillerWords: ["um", "basically"])
        manager.removeWord("um")
        XCTAssertEqual(manager.fillerWords, ["basically"])
    }

    func test_addWord_rejectsDuplicate() {
        let manager = makeManager(fillerWords: ["um"])
        XCTAssertFalse(manager.addWord("UM"), "duplicates are rejected case-insensitively")
        XCTAssertEqual(manager.fillerWords, ["um"])
    }

    /// Isolated defaults domain so list edits never touch the real one.
    private func makeManager(fillerWords: [String]) -> FillerWordManager {
        FillerWordManager(defaults: isolatedDefaults(), fillerWords: fillerWords)
    }
}
