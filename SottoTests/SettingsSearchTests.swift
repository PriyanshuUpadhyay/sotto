import XCTest
@testable import Sotto

@MainActor
final class SettingsSearchTests: XCTestCase {

    // The sum of every indexed tab's section cases — the only legitimate size
    // of a label/section index. v1 must NOT index deeper than this (no
    // per-control value entries). Models and Vocabulary are excluded: both live
    // in the window sidebar, not the Settings rail.
    private var expectedIndexCount: Int {
        GeneralTab.GeneralTabSection.allCases.count
            + ShortcutsTab.ShortcutsTabSection.allCases.count
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
    }

    /// Dictionary is a window sidebar destination, so it is NOT reachable from
    /// the Settings search field — the command palette reaches it instead.
    func test_index_holdsNoVocabularyEntries() {
        XCTAssertFalse(SettingsSearch.index.contains { $0.tab == .vocabulary },
                       "Vocabulary sections must not be indexed — Dictionary lives in the window sidebar, not the Settings rail")
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

    // MARK: - Control keywords resolve to the section that owns the control

    func test_controlKeywordMatch_findsTheSectionThatOwnsTheControl() {
        let search = SettingsSearch()

        let haptics = search.filter("haptic")
        XCTAssertTrue(haptics.contains { $0.tab == .general && $0.label == "Sound Feedback" },
                      "a control name must find its section: haptics live in General/Sound Feedback")

        let export = search.filter("export")
        XCTAssertTrue(export.contains { $0.tab == .advanced && $0.label == "Backup & Restore" },
                      "export lives in Advanced/Backup & Restore")

        let accessibility = search.filter("accessibility")
        XCTAssertTrue(accessibility.contains { $0.tab == .general && $0.label == "Permissions" })
    }

    func test_everySectionCarriesControlKeywords() {
        for entry in SettingsSearch.index {
            XCTAssertFalse(entry.keywords.isEmpty,
                           "\(entry.tab.title)/\(entry.label) must name the controls it holds")
        }
    }

    // MARK: - Negative anchor: index is section LABELS + their control
    // keywords, never one entry per live control value.

    func test_index_countEqualsSumOfSectionLabels_notControlValues() {
        XCTAssertEqual(SettingsSearch.index.count, expectedIndexCount,
                       "index must hold exactly one entry per section — control names are keywords on that entry, not extra entries")
    }
}
