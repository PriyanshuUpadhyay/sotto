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
}
