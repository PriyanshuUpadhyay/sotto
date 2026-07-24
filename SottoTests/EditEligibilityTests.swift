import Testing
@testable import Sotto

@Suite struct EditEligibilityTests {
    @Test("rejects whitespace-only / identical")
    func identical() {
        #expect(EditEligibility.classify(enhanced: "see you tomorrow", final: "see you tomorrow") == nil)
    }
    @Test("rejects pure append (continuation typing)")
    func pureAppend() {
        // "See you tomorrow" → "See you tomorrow at 5pm" is continuation, not a correction
        #expect(EditEligibility.classify(enhanced: "see you tomorrow", final: "see you tomorrow at 5pm") == nil)
    }
    @Test("rejects whole-text divergence (low overlap)")
    func divergence() {
        #expect(EditEligibility.classify(enhanced: "the cat sat on the mat", final: "completely different sentence here now") == nil)
    }
    @Test("accepts a substituted proper noun as spelling/style")
    func properNoun() {
        let kind = EditEligibility.classify(enhanced: "met with priyanshu today", final: "met with Priyanshu today")
        #expect(kind != nil)
    }
    @Test("rejects pure duplication (paste/capture artifact, seam glued)")
    func pureDuplication() {
        // Capture bug: final is enhanced concatenated N times with no space at the seam.
        let e = "Redo the clean and just create the PR. Do not merge."
        let f = e + e + e + e
        #expect(EditEligibility.classify(enhanced: e, final: f) == nil)
    }
    @Test("rejects pure append even when enhanced ends in punctuation")
    func appendAcrossPunctuation() {
        // "…fix these migrations." → "…fix these migrations and resolve conflicts" is continuation.
        #expect(EditEligibility.classify(
            enhanced: "do the changes that fix these migrations.",
            final: "do the changes that fix these migrations and resolve conflicts") == nil)
    }
    @Test("keeps an edit that corrects the body AND appends (real signal)")
    func bodyCorrectionWithAppend() {
        // Mishear corrected mid-body (wall talk → vault doc) plus a trailing word.
        // Token-set overlap stays high, so the new append/punctuation guards must
        // NOT eat it — this is the learnable shape (cf. real record #20).
        let kind = EditEligibility.classify(
            enhanced: "you can also look at the logs and find cases where pages should be generated using the wall talk file",
            final: "you can also look at the logs and find cases where pages should be generated using the vault doc file now")
        #expect(kind != nil)
    }
}
