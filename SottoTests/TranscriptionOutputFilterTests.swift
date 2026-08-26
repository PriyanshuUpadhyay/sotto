import XCTest
@testable import Sotto

/// Covers `TranscriptionOutputFilter.cleaning`, the whole rule set the delivered
/// transcript passes through. `filter(_:)` is the same pipeline reading the
/// `FillerWordManager` singleton, so exercising it here needs no app state.
final class TranscriptionOutputFilterTests: XCTestCase {

    private func clean(_ text: String, removeFillerWords: Bool = false, fillerWords: [String] = []) -> String {
        TranscriptionOutputFilter.cleaning(text, removeFillerWords: removeFillerWords, fillerWords: fillerWords)
    }

    // MARK: Tag blocks

    func testRemovesATagBlockWithItsContents() {
        XCTAssertEqual(clean("keep this <THINK>drop this</THINK> and this"), "keep this and this")
    }

    func testRemovesATagBlockWithAttributes() {
        XCTAssertEqual(clean("before <note id=\"1\">inside</note> after"), "before after")
    }

    func testRemovesATagBlockSpanningLines() {
        XCTAssertEqual(clean("a <x>one\ntwo</x> b"), "a b")
    }

    func testKeepsAnUnclosedTag() {
        XCTAssertEqual(clean("a <THINK> b"), "a <THINK> b")
    }

    func testKeepsTextWhoseClosingTagDoesNotMatchTheOpeningOne() {
        XCTAssertEqual(clean("a <one>x</two> b"), "a <one>x</two> b")
    }

    // MARK: Bracketed hallucinations

    func testRemovesSquareRoundAndCurlyBracketedRuns() {
        XCTAssertEqual(clean("a [music] b (laughs) c {noise} d"), "a b c d")
    }

    func testRemovesOnlyTheShortestBracketedRun() {
        XCTAssertEqual(clean("a [one] keep [two] b"), "a keep b")
    }

    func testKeepsAnUnclosedBracket() {
        XCTAssertEqual(clean("a [music b"), "a [music b")
    }

    // MARK: Filler words

    func testDropsListedFillerWordsWhenRemovalIsOn() {
        XCTAssertEqual(clean("so um this is the plan", removeFillerWords: true, fillerWords: ["um"]),
                       "so this is the plan")
    }

    func testKeepsFillerWordsWhenRemovalIsOff() {
        XCTAssertEqual(clean("so um this is the plan", removeFillerWords: false, fillerWords: ["um"]),
                       "so um this is the plan")
    }

    func testKeepsAWordThatOnlyContainsAFillerWord() {
        XCTAssertEqual(clean("a drumbeat", removeFillerWords: true, fillerWords: ["um"]), "a drumbeat")
    }

    // MARK: Whitespace

    func testCollapsesRunsOfWhitespaceAndTrimsTheEnds() {
        XCTAssertEqual(clean("  a   b\n\nc  "), "a b c")
    }

    func testReturnsAnEmptyStringWhenEverythingWasRemoved() {
        XCTAssertEqual(clean("[music]"), "")
    }

    func testLeavesACleanTranscriptUnchanged() {
        XCTAssertEqual(clean("the quick brown fox"), "the quick brown fox")
    }

    // MARK: Combined rules

    func testDropsTheCommaThatFollowsARemovedFillerWord() {
        XCTAssertEqual(clean("well, um, done", removeFillerWords: true, fillerWords: ["um"]), "well, done")
    }

    func testAppliesEveryRuleToOneTranscript() {
        XCTAssertEqual(
            clean("  <THINK>plan</THINK> so [cough] um   the   report.  ",
                  removeFillerWords: true, fillerWords: ["um"]),
            "so the report."
        )
    }
}
