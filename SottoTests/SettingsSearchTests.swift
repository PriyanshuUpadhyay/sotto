import XCTest
@testable import Sotto

@MainActor
final class SettingsSearchTests: XCTestCase {

    // The sum of every indexed tab's section cases — the only legitimate size
    // of a label/section index. v1 must NOT index deeper than this (no
    // per-control value entries). The sidebar is flat, so ONE search field
    // answers for every destination: Dictionary and Models are indexed too.
    private var expectedIndexCount: Int {
        VocabularyTab.VocabularyTabSection.allCases.count
            + ModelsTab.ModelsTabSection.allCases.count
            + GeneralTab.GeneralTabSection.allCases.count
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

    /// The sidebar search spans every destination: a vocabulary query finds the
    /// Dictionary row's sections, and a model query finds the Models page.
    func test_index_holdsEveryDestination() {
        for tab in SettingsTab.allCases {
            XCTAssertTrue(SettingsSearch.index.contains { $0.tab == tab },
                          "\(tab.title) must be indexed — the flat sidebar has one search field for the whole window")
        }
    }

    func test_vocabularyQuery_findsTheDictionarySections() {
        let search = SettingsSearch()
        XCTAssertTrue(search.filter("replacement").contains { $0.tab == .vocabulary && $0.label == "Word Replacements" })
        XCTAssertTrue(search.filter("um").contains { $0.tab == .vocabulary && $0.label == "Filler Words" })
    }

    func test_modelQuery_findsTheModelsPage() {
        let search = SettingsSearch()
        XCTAssertTrue(search.filter("whisper").contains { $0.tab == .models && $0.label == "Transcription Models" })
    }

    // MARK: - Sidebar narrowing spans the whole window

    func test_filteredTabs_emptyQuery_isEverySidebarRow() {
        XCTAssertEqual(SettingsSearch(query: "").filteredTabs(), SottoWindowTab.allCases)
        XCTAssertEqual(SettingsSearch(query: "  ").filteredTabs(), SottoWindowTab.allCases)
    }

    func test_filteredTabs_narrowsToTheRowThatOwnsTheMatch() {
        XCTAssertEqual(SettingsSearch(query: "replacement").filteredTabs(), [.dictionary])
        XCTAssertEqual(SettingsSearch(query: "whisper").filteredTabs(), [.models])
        XCTAssertEqual(SettingsSearch(query: "haptic").filteredTabs(), [.general])
        XCTAssertEqual(SettingsSearch(query: "export").filteredTabs(), [.advanced])
    }

    /// History carries no indexed sections, so it survives only on its own name.
    func test_filteredTabs_matchesADestinationByItsOwnTitle() {
        XCTAssertEqual(SettingsSearch(query: "history").filteredTabs(), [.history])
        XCTAssertTrue(SettingsSearch(query: "dictionary").filteredTabs().contains(.dictionary))
    }

    func test_filteredTabs_unmatchedQuery_isEmpty() {
        XCTAssertTrue(SettingsSearch(query: "zzz-no-such-setting-zzz").filteredTabs().isEmpty)
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
