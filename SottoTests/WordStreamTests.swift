import XCTest
@testable import Sotto

/// Suffix-diff contract for the capsule word tape (`WordStream`): extends
/// animate (`.appended`, fresh identities only for new words), any correction
/// — earlier-word rewrite, last-word refinement, trim — is `.rewritten`
/// (instant swap), and identical/whitespace-only partials are `.none`.
final class WordStreamTests: XCTestCase {

    func testInitSeedsWordsFromPartial() {
        let s = WordStream(partial: "ship the parser")
        XCTAssertEqual(s.words.map(\.text), ["ship", "the", "parser"])
    }

    func testFirstWordsFromEmptyAreAppended() {
        var s = WordStream()
        XCTAssertEqual(s.ingest("ship the"), .appended)
        XCTAssertEqual(s.words.map(\.text), ["ship", "the"])
    }

    func testExtensionAppendsOnlyNewWordsKeepingPrefixIdentity() {
        var s = WordStream(partial: "ship the")
        let prefixIDs = s.words.map(\.id)
        XCTAssertEqual(s.ingest("ship the parser today"), .appended)
        XCTAssertEqual(s.words.map(\.text), ["ship", "the", "parser", "today"])
        XCTAssertEqual(Array(s.words.map(\.id).prefix(2)), prefixIDs)
        XCTAssertEqual(Set(s.words.map(\.id)).count, 4, "ids stay unique")
    }

    func testIdenticalPartialIsNoChange() {
        var s = WordStream(partial: "ship the parser")
        XCTAssertEqual(s.ingest("ship the parser"), .none)
    }

    func testWhitespaceOnlyDifferenceIsNoChange() {
        var s = WordStream(partial: "ship the parser")
        XCTAssertEqual(s.ingest("  ship  the\nparser "), .none)
        XCTAssertEqual(s.words.map(\.text), ["ship", "the", "parser"])
    }

    func testLastWordRefinementIsRewriteWithStablePrefix() {
        var s = WordStream(partial: "ship the par")
        let prefixIDs = Array(s.words.map(\.id).prefix(2))
        let refinedID = s.words[2].id
        XCTAssertEqual(s.ingest("ship the parser"), .rewritten)
        XCTAssertEqual(s.words.map(\.text), ["ship", "the", "parser"])
        XCTAssertEqual(Array(s.words.map(\.id).prefix(2)), prefixIDs)
        XCTAssertNotEqual(s.words[2].id, refinedID, "corrected word is a fresh identity")
    }

    func testEarlierWordCorrectionIsRewrite() {
        var s = WordStream(partial: "ship a parser")
        let firstID = s.words[0].id
        XCTAssertEqual(s.ingest("ship the parser"), .rewritten)
        XCTAssertEqual(s.words.map(\.text), ["ship", "the", "parser"])
        XCTAssertEqual(s.words[0].id, firstID, "untouched prefix keeps identity")
    }

    func testTrimIsRewrite() {
        var s = WordStream(partial: "ship the parser")
        XCTAssertEqual(s.ingest("ship the"), .rewritten)
        XCTAssertEqual(s.words.map(\.text), ["ship", "the"])
    }

    func testEmptyPartialClearsWords() {
        var s = WordStream(partial: "ship the")
        XCTAssertEqual(s.ingest(""), .rewritten)
        XCTAssertTrue(s.words.isEmpty)
        XCTAssertEqual(s.ingest(""), .none)
    }

    // MARK: - Recency window

    private func sentence(_ n: Int) -> String {
        (1...n).map { "w\($0)" }.joined(separator: " ")
    }

    func testWindowCapsVisibleTail() {
        let s = WordStream(partial: sentence(20))
        XCTAssertEqual(s.words.count, WordStream.windowMax)
        XCTAssertEqual(s.words.first?.text, "w\(20 - WordStream.windowMax + 1)")
        XCTAssertEqual(s.words.last?.text, "w20")
    }

    func testExtensionPastWindowStillAppends() {
        var s = WordStream(partial: sentence(20))
        let survivingIDs = s.words.map(\.id)
        XCTAssertEqual(s.ingest(sentence(20) + " more"), .appended)
        XCTAssertEqual(s.words.count, WordStream.windowMax)
        XCTAssertEqual(s.words.last?.text, "more")
        XCTAssertEqual(Array(s.words.map(\.id).prefix(WordStream.windowMax - 1)),
                       Array(survivingIDs.dropFirst()),
                       "window slides by one; kept words keep identity")
    }

    func testCappedThenTrimKeepsLatestWords() {
        // 17 words push w1 behind the window; trimming back to a 16-word
        // prefix must show exactly w1..w16 — the last word must NOT be lost
        // to stale window-offset bookkeeping.
        var s = WordStream(partial: sentence(17))
        XCTAssertEqual(s.ingest(sentence(16)), .rewritten)
        XCTAssertEqual(s.words.map(\.text), (1...16).map { "w\($0)" })
    }

    func testShrinkBelowWindowShowsAllRemainingWords() {
        var s = WordStream(partial: sentence(20))
        XCTAssertEqual(s.ingest(sentence(5)), .rewritten)
        XCTAssertEqual(s.words.map(\.text), (1...5).map { "w\($0)" })
        XCTAssertEqual(s.ingest(sentence(5) + " more"), .appended)
    }

    func testRewriteInsideHiddenPrefixIsDetectedAsRewrite() {
        // Same-length rewrite of a word that sits behind the visible window:
        // still a .rewritten (instant swap), never a silent .none.
        var s = WordStream(partial: sentence(20))
        let visibleTexts = s.words.map(\.text)
        let corrected = "wX " + sentence(20).split(separator: " ").dropFirst().joined(separator: " ")
        XCTAssertEqual(s.ingest(corrected), .rewritten)
        XCTAssertEqual(s.words.map(\.text), visibleTexts, "visible tail texts unchanged")
    }

    func testFullRewriteReplacesEverything() {
        var s = WordStream(partial: sentence(20))
        XCTAssertEqual(s.ingest("fresh start"), .rewritten)
        XCTAssertEqual(s.words.map(\.text), ["fresh", "start"])
        XCTAssertEqual(s.ingest("fresh start again"), .appended)
    }
}
