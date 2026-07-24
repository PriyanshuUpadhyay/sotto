import XCTest
@testable import Sotto

@MainActor
final class SettingsSearchTests: XCTestCase {

    // The sum of every indexed tab's section cases — the only legitimate size
    // of a label/section index. v1 must NOT index deeper than this (no
    // per-control value entries). Models is excluded: it lives in the window
    // sidebar, not the Settings rail (2026-07 revamp).
    private var expectedIndexCount: Int {
        GeneralTab.GeneralTabSection.allCases.count
            + ShortcutsTab.ShortcutsTabSection.allCases.count
            + VocabularyTab.VocabularyTabSection.allCases.count
            + AdvancedTab.AdvancedTabSection.allCases.count
    }

    // MARK: - Empty query returns all entries

    func test_emptyQuery_returnsAllEntries() {
        let search = SettingsSearch()
        XCTAssertEqual(search.filter(""), SettingsSearch.index)
        XCTAssertEqual(search.filter("   ").count, SettingsSearch.index.count)
    }

    // MARK: - Label match narrows and excludes non-matches

    func test_sectionLabelMatch_returnsMatchingEntryAndExcludesOthers() {
        let search = SettingsSearch()

        let paste = search.filter("paste")
        XCTAssertTrue(paste.contains { $0.tab == .shortcuts && $0.label.localizedCaseInsensitiveContains("paste") },
                      "expected a Shortcuts/Paste Last Transcription entry")
        XCTAssertFalse(paste.contains { $0.tab == .general && $0.label == "Audio Input" },
                       "non-matching entries must be excluded")

        let audio = search.filter("audio")
        XCTAssertTrue(audio.contains { $0.tab == .general && $0.label.localizedCaseInsensitiveContains("audio") })

        let dictionary = search.filter("dictionary")
        XCTAssertTrue(dictionary.contains { $0.tab == .vocabulary && $0.label.localizedCaseInsensitiveContains("dictionary") })
    }

    // MARK: - Case-insensitive

    func test_match_isCaseInsensitive() {
        let search = SettingsSearch()
        XCTAssertEqual(search.filter("AUDIO"), search.filter("audio"))
        XCTAssertFalse(search.filter("AUDIO").isEmpty)
    }

    // MARK: - No match returns empty

    func test_unmatchedQuery_returnsEmpty() {
        let search = SettingsSearch()
        XCTAssertTrue(search.filter("zzz-no-such-setting-zzz").isEmpty)
    }

    // MARK: - Negative anchor: index is section LABELS, not control values

    func test_index_countEqualsSumOfSectionLabels_notControlValues() {
        XCTAssertEqual(SettingsSearch.index.count, expectedIndexCount,
                       "index must hold exactly one entry per section label — not per live control value")
    }
}
