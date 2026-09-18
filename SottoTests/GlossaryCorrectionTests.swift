import Testing
@testable import Sotto

@Suite struct GlossaryCorrectionTests {

    static let glossary = ["Claude", "Herdr", "Ghostty", "pagination", "cmux"]

    // MARK: - Grammar

    @Test("grammar constrains replace to a closed alternation of glossary terms")
    func grammarAlternation() {
        let g = GlossaryCorrection.grammar(glossary: Self.glossary)
        #expect(g?.contains("replace ::=") == true)
        for term in Self.glossary {
            #expect(g?.contains(term) == true, "\(term) missing from the alternation")
        }
        // The empty array must stay legal so "nothing is wrong" is expressible.
        #expect(g?.contains("\"[]\"") == true)
    }

    @Test("empty glossary yields no grammar")
    func grammarEmpty() {
        #expect(GlossaryCorrection.grammar(glossary: []) == nil)
        #expect(GlossaryCorrection.grammar(glossary: ["  "]) == nil)
    }

    // MARK: - Parse

    @Test("parses a patch list")
    func parseList() {
        let out = GlossaryCorrection.parse(#"[{"find":"clouds","replace":"Claude"}]"#)
        #expect(out == [GlossaryCorrection.Patch(find: "clouds", replace: "Claude")])
    }

    @Test("unparseable or empty output yields no patches, never a throw")
    func parseGarbage() {
        #expect(GlossaryCorrection.parse("not json").isEmpty)
        #expect(GlossaryCorrection.parse("[]").isEmpty)
        #expect(GlossaryCorrection.parse("").isEmpty)
        #expect(GlossaryCorrection.parse(#"[{"find":"","replace":"Claude"}]"#).isEmpty)
    }

    // MARK: - Apply

    @Test("applies a real mishear")
    func applyReal() {
        let out = GlossaryCorrection.apply(
            [.init(find: "clouds", replace: "Claude")],
            to: "the clouds auto selection is broken", glossary: Self.glossary)
        #expect(out == "the Claude auto selection is broken")
    }

    @Test("applies a merge-shatter span")
    func applyShatter() {
        let out = GlossaryCorrection.apply(
            [.init(find: "page nation", replace: "pagination")],
            to: "For page nation I was thinking", glossary: Self.glossary)
        #expect(out == "For pagination I was thinking")
    }

    @Test("a replacement outside the glossary is refused")
    func rejectsUnknownReplacement() {
        let text = "the clouds auto selection"
        let out = GlossaryCorrection.apply(
            [.init(find: "clouds", replace: "Weather")], to: text, glossary: Self.glossary)
        #expect(out == text)
    }

    @Test("a find that is not in the transcript is refused")
    func rejectsAbsentFind() {
        let text = "nothing to see here"
        let out = GlossaryCorrection.apply(
            [.init(find: "clouds", replace: "Claude")], to: text, glossary: Self.glossary)
        #expect(out == text)
    }

    @Test("a find longer than the word cap cannot swallow a clause")
    func rejectsLongFind() {
        let text = "we should look at the whole thing again"
        let out = GlossaryCorrection.apply(
            [.init(find: "look at the whole thing", replace: "Claude")],
            to: text, glossary: Self.glossary)
        #expect(out == text)
    }

    @Test("a no-op patch changes nothing")
    func rejectsNoOp() {
        let text = "Claude is fine"
        let out = GlossaryCorrection.apply(
            [.init(find: "Claude", replace: "Claude")], to: text, glossary: Self.glossary)
        #expect(out == text)
    }

    @Test("content outside the named spans is never touched")
    func leavesRestAlone() {
        let text = "the clouds auto selection is not working because Fable is exhausted"
        let out = GlossaryCorrection.apply(
            [.init(find: "clouds", replace: "Claude")], to: text, glossary: Self.glossary)
        #expect(out == "the Claude auto selection is not working because Fable is exhausted")
        // Word count is preserved — no rewrite, no drop.
        #expect(out.split(separator: " ").count == text.split(separator: " ").count)
    }

    @Test("several patches apply in one pass")
    func multiplePatches() {
        let out = GlossaryCorrection.apply(
            [.init(find: "herder", replace: "Herdr"),
             .init(find: "ghost team", replace: "Ghostty")],
            to: "ghost team commands for herder", glossary: Self.glossary)
        #expect(out == "Ghostty commands for Herdr")
    }
}
