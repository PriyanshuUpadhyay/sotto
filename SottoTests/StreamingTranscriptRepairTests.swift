import Testing
@testable import Sotto

@Suite struct StreamingTranscriptRepairTests {
    // MARK: appendingDroppedTail — cases taken from real 2026-10 dictations

    @Test("dropped trailing words are appended; the aligned last word takes the batch punctuation")
    func appendsTail() {
        let out = StreamingTranscriptRepair.appendingDroppedTail(
            streaming: "3D objects, and so on. Just that it should be.",
            batch: "3D objects and so on. Just that it should be really exact.")
        #expect(out == "3D objects, and so on. Just that it should be really exact.")
    }

    @Test("earlier paragraph breaks survive the repair")
    func keepsParagraphs() {
        let out = StreamingTranscriptRepair.appendingDroppedTail(
            streaming: "First part here.\n\nYou can use Compose Yo MCP connection to",
            batch: "First part here. You can use Compose Yo MCP connection to check it out.")
        #expect(out == "First part here.\n\nYou can use Compose Yo MCP connection to check it out.")
    }

    @Test("no repair when the endings disagree (batch hallucination after a different last word)")
    func endingsDisagree() {
        let streaming = "please translate this for adobe"
        #expect(StreamingTranscriptRepair.appendingDroppedTail(
            streaming: streaming, batch: "please translate this for atovi ignuja bolke bura") == streaming)
    }

    @Test("a one-word tail and an over-long tail are both left alone")
    func tailBounds() {
        let streaming = "we can ship this today"
        #expect(StreamingTranscriptRepair.appendingDroppedTail(
            streaming: streaming, batch: "we can ship this today uh") == streaming)
        let long = streaming + " " + Array(repeating: "word", count: 13).joined(separator: " ")
        #expect(StreamingTranscriptRepair.appendingDroppedTail(streaming: streaming, batch: long) == streaming)
    }

    @Test("identical or shorter batch text changes nothing")
    func noTail() {
        let s = "Are people getting rate limited based on the messages?"
        #expect(StreamingTranscriptRepair.appendingDroppedTail(streaming: s, batch: s) == s)
        #expect(StreamingTranscriptRepair.appendingDroppedTail(streaming: s, batch: "Are people") == s)
    }

    // MARK: applyingSwaps

    @Test("multi-word phrase swap keeps trailing punctuation and surrounding whitespace")
    func multiWordSwap() {
        let out = StreamingTranscriptRepair.applyingSwaps(
            [(original: "Compose Yo", replacement: "Composio"), (original: "dot files.", replacement: "dotfiles")],
            to: "Use Compose Yo now.\n\nCheck the dot files.")
        #expect(out == "Use Composio now.\n\nCheck the dotfiles.")
    }

    @Test("each swap takes one occurrence; a phrase missing from the streaming text is skipped")
    func swapOccurrences() {
        let out = StreamingTranscriptRepair.applyingSwaps(
            [(original: "herder", replacement: "herdr"), (original: "absent", replacement: "X")],
            to: "Herder works, herder too.")
        #expect(out == "herdr works, herder too.")
    }

    // MARK: boostableTerms

    @Test("short terms and terms whose tail is a common word are not boosted")
    func boostable() {
        let words: Set<String> = ["able", "code", "otto"]
        let out = StreamingTranscriptRepair.boostableTerms(
            ["Fable", "Xcode", "Ink", "cua", "Opus", "Claude", "herdr", "Composio"],
            isDictionaryWord: words.contains)
        #expect(out == ["Claude", "herdr", "Composio"])
    }
}
