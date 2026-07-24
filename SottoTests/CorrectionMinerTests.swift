import Testing
import Foundation
@testable import Sotto

@Suite struct CorrectionMinerTests {
    /// An `.edit` record whose enhanced→final diff yields the pair (cloud → Claude)
    /// unless custom texts are supplied.
    private func editRecord(enhanced: String = "use cloud here",
                            final: String = "use Claude here",
                            tid: UUID = UUID()) -> EnhancementEditRecord {
        EnhancementEditRecord(rawText: "", enhancedText: enhanced, finalText: final,
                              appBundleID: nil, transcriptionID: tid, enhancedHash: "",
                              editKind: .spelling, signalSource: .edit)
    }

    private func mine(_ records: [EnhancementEditRecord],
                      vocab: Set<String> = [],
                      replacements: Set<String> = [],
                      dismissed: Set<String> = []) -> [CorrectionSuggestion] {
        CorrectionMiner.mine(records: records, existingVocabulary: vocab,
                             existingReplacements: replacements, dismissed: dismissed)
    }

    @Test("pair corrected in 3 distinct dictations is suggested; 2 is below threshold")
    func threshold() {
        #expect(mine([editRecord(), editRecord()]).isEmpty)
        let three = mine([editRecord(), editRecord(), editRecord()])
        #expect(three.count == 1)
        #expect(three[0].original == "cloud")
        #expect(three[0].replacement == "Claude")
        #expect(three[0].count == 3)
    }

    @Test("repeats within the SAME dictation count once (across dictations, not occurrences)")
    func distinctDictations() {
        let tid = UUID()
        // Same transcriptionID reused → one dictation, even across 3 records.
        let dup = [editRecord(tid: tid), editRecord(tid: tid), editRecord(tid: tid)]
        #expect(mine(dup).isEmpty)
    }

    @Test("case-only substitutions are ignored")
    func caseOnly() {
        let recs = (0..<3).map { _ in editRecord(enhanced: "met priyanshu now", final: "met Priyanshu now") }
        #expect(mine(recs).isEmpty)
    }

    @Test("replacement already in vocabulary is dropped")
    func alreadyInVocab() {
        let recs = (0..<3).map { _ in editRecord() }
        #expect(mine(recs, vocab: ["claude"]).isEmpty)
    }

    @Test("pair already a word-replacement mapping is dropped")
    func alreadyReplacement() {
        let recs = (0..<3).map { _ in editRecord() }
        let key = CorrectionMiner.pairKey(original: "cloud", replacement: "Claude")
        #expect(mine(recs, replacements: [key]).isEmpty)
    }

    @Test("comma-separated replacement originals suppress the matching mined pair")
    func commaSeparatedReplacementSuppresses() {
        let recs = (0..<3).map { _ in editRecord() }  // mines cloud→Claude
        // A "cloud, claud → Claude" entry yields one key per variant, so the
        // mined cloud→Claude pair is suppressed even though the whole
        // originalText ("cloud, claud") doesn't equal the mined original.
        let keys = Set(CorrectionMiner.replacementPairKeys(original: "cloud, claud", replacement: "Claude"))
        #expect(keys.contains(CorrectionMiner.pairKey(original: "cloud", replacement: "Claude")))
        #expect(keys.contains(CorrectionMiner.pairKey(original: "claud", replacement: "Claude")))
        #expect(mine(recs, replacements: keys).isEmpty)
    }

    @Test("dismissed pair is dropped")
    func dismissedPair() {
        let recs = (0..<3).map { _ in editRecord() }
        let key = CorrectionMiner.pairKey(original: "cloud", replacement: "Claude")
        #expect(mine(recs, dismissed: [key]).isEmpty)
    }

    @Test("only .edit records are mined; thumbsDown/acceptedUnchanged ignored")
    func onlyEditRecords() {
        let down = (0..<3).map { _ -> EnhancementEditRecord in
            EnhancementEditRecord(rawText: "", enhancedText: "use cloud here", finalText: "use Claude here",
                                  appBundleID: nil, transcriptionID: UUID(), enhancedHash: "",
                                  editKind: .spelling, signalSource: .thumbsDown)
        }
        #expect(mine(down).isEmpty)
    }

    @Test("phrase rewrite yields ZERO suggestions even after 3 occurrences (no cross-product pairs)")
    func phraseRewriteNoCrossProduct() {
        // "the quick fix" → "a fast patch": a 3-token span rewrite, not three
        // 1:1 word substitutions — must never mint pairs like quick→patch.
        let recs = (0..<3).map { _ in
            editRecord(enhanced: "we need the quick fix today", final: "we need a fast patch today")
        }
        #expect(mine(recs).isEmpty)
    }

    @Test("insertion into a changed span yields no pairs (1 delete vs 2 inserts)")
    func insertionNoPairs() {
        // "cloud" replaced by TWO tokens — ambiguous alignment, must not pair.
        let recs = (0..<3).map { _ in
            editRecord(enhanced: "use cloud here", final: "use Claude Code here")
        }
        #expect(mine(recs).isEmpty)
    }

    @Test("suggestions sorted by count desc then replacement asc")
    func sorting() {
        let cloud = (0..<3).map { _ in editRecord() }                                   // cloud→Claude ×3
        let sonnet = (0..<5).map { _ in editRecord(enhanced: "a sonet b", final: "a Sonnet b") } // ×5
        let out = mine(cloud + sonnet)
        #expect(out.map { $0.replacement } == ["Sonnet", "Claude"])
    }
}
