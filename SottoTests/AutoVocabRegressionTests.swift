import Testing
@testable import Sotto

// Regression: after the AX edit-learning removal, the auto-vocabulary path's
// core diff (single-word substitutions between pasted + edited text) must
// still work — the engine the surviving finalize() feeds into NER.
@Suite struct AutoVocabRegressionTests {
    // The engine compares case-insensitively, so it surfaces genuine word
    // corrections (the substitution the NER vocab path learns from) — a
    // case-only change is intentionally NOT a substitution.
    @Test("single-word substitution is detected")
    func detectsSubstitution() {
        let subs = WordDiffEngine.findSingleWordSubstitutions(
            original: "met with rueben today", edited: "met with Reuben today")
        #expect(subs.contains { $0.original.lowercased() == "rueben" && $0.replacement == "Reuben" })
    }
    @Test("identical text yields no substitutions")
    func noChange() {
        #expect(WordDiffEngine.findSingleWordSubstitutions(
            original: "hello world", edited: "hello world").isEmpty)
    }

    // finalize() mines with CorrectionMiner.alignedSubstitutions, not the engine
    // above: the engine cross-products unequal-length changed spans, minting
    // pairs the user never made (the spurious-auto-add bug).
    @Test("multi-word rewrite yields no substitution pairs")
    func multiWordRewriteYieldsNoPairs() {
        let subs = CorrectionMiner.alignedSubstitutions(
            original: "call the meeting tomorrow", edited: "call our long sync")
        #expect(subs.isEmpty)
    }

    @Test("genuine single-word swap is still mined")
    func genuineSwapMined() {
        let subs = CorrectionMiner.alignedSubstitutions(
            original: "met with rueben today", edited: "met with Reuben today")
        #expect(subs.contains { $0.original == "rueben" && $0.replacement == "Reuben" })
    }

    // Merge shatter — the dominant OOV failure: a proper noun transcribed as two
    // dictionary words the user fuses back. Both fragments pass spellcheck, so
    // nothing else recovers it.
    @Test("merge of fragments that spell the inserted word is mined")
    func mergeShatterMined() {
        let subs = CorrectionMiner.alignedSubstitutions(
            original: "met with para keet today", edited: "met with Parakeet today")
        #expect(subs.contains { $0.original == "para keet" && $0.replacement == "Parakeet" })
    }

    @Test("merge into a hyphenated word is mined")
    func mergeIntoHyphenated() {
        let subs = CorrectionMiner.alignedSubstitutions(original: "e mail", edited: "e-mail")
        #expect(subs.contains { $0.original == "e mail" && $0.replacement == "e-mail" })
    }

    @Test("many-to-one span that is not a literal fusion stays dropped")
    func nonFusionManyToOneDropped() {
        let subs = CorrectionMiner.alignedSubstitutions(
            original: "the meeting tomorrow", edited: "sync tomorrow")
        #expect(subs.isEmpty)
    }

    // Two-token spans align positionally — the common two-word proper-noun fix
    // that strict 1:1 alignment used to drop entirely.
    @Test("two-token span replaced by two tokens mines both pairs")
    func equalLengthSpanMinesPositionalPairs() {
        let subs = CorrectionMiner.alignedSubstitutions(
            original: "met with jon smyth today", edited: "met with John Smith today")
        #expect(subs.count == 2)
        #expect(subs.contains { $0.original == "jon" && $0.replacement == "John" })
        #expect(subs.contains { $0.original == "smyth" && $0.replacement == "Smith" })
    }

    // Three is where the shape stops being a name fix and starts matching
    // ordinary phrase rewrites, so positional pairing stops at two.
    @Test("equal-length span of 3+ tokens stays dropped")
    func longEqualLengthSpanDropped() {
        #expect(CorrectionMiner.alignedSubstitutions(
            original: "we need the quick fix today", edited: "we need a fast patch today").isEmpty)
        #expect(CorrectionMiner.alignedSubstitutions(
            original: "call the meeting tomorrow now", edited: "ping our long sync now").isEmpty)
    }

    // Only the real correction is mined when one word of a two-word fix changed
    // case only: the diff's LCS matches case-insensitively, so the case-only
    // token anchors as equal and never becomes half of a positional pair.
    @Test("case-only half of a two-word fix is not mined")
    func caseOnlyHalfNotMined() {
        let subs = CorrectionMiner.alignedSubstitutions(
            original: "met with jon smyth today", edited: "met with Jon Smith today")
        #expect(subs.count == 1)
        #expect(subs.contains { $0.original == "smyth" && $0.replacement == "Smith" })
    }

    @Test("OOV gate rejects dictionary words, accepts unknown terms")
    func oovGate() {
        // Stubbed dictionary — the real gate uses NSSpellChecker, whose verdicts
        // depend on the host's spell language and user-learned words. The gate
        // lowercases before asking, so the stub only ever sees lowercase.
        let known: Set<String> = ["same", "filter", "no", "hunter"]
        let isMisspelled: (String) -> Bool = { !known.contains($0) }

        #expect(!AutoLearnVocabularyService.isLikelyProperTerm("Same", isMisspelled: isMisspelled))
        #expect(!AutoLearnVocabularyService.isLikelyProperTerm("Filter", isMisspelled: isMisspelled))
        #expect(!AutoLearnVocabularyService.isLikelyProperTerm("No", isMisspelled: isMisspelled))
        #expect(AutoLearnVocabularyService.isLikelyProperTerm("Jx4Z", isMisspelled: isMisspelled))
        // Multi-word entity passes on its one unknown component.
        #expect(AutoLearnVocabularyService.isLikelyProperTerm("Same Jx4Z", isMisspelled: isMisspelled))
    }
}
