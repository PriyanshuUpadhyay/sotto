import Testing
@testable import Sotto

/// Cases are the real softenings the on-device model produced over one week of
/// dictation, plus the ordinary cleanups that must survive the guard untouched.
@Suite struct VerbatimWordGuardTests {

    // MARK: Restores what the model softened

    @Test("restores a softened word in the middle of a sentence")
    func restoresSoftenedWord() {
        let raw = "see if there is a chance of redundancy and a fucked up PR"
        let out = "See if there is a chance of redundancy and a messed up PR."
        #expect(VerbatimWordGuard.restore(raw: raw, output: out).contains("fucked"))
        #expect(!VerbatimWordGuard.restore(raw: raw, output: out).contains("messed"))
    }

    @Test("restores a two-word phrase replaced by one milder word")
    func restoresMultiWordSoftening() {
        let raw = "we keep repeating the same fuck ups every sprint"
        let out = "We keep repeating the same mistakes every sprint."
        let restored = VerbatimWordGuard.restore(raw: raw, output: out)
        #expect(restored.contains("fuck ups"))
        #expect(!restored.contains("mistakes"))
    }

    @Test("leaves an already-faithful output alone")
    func keepsFaithfulOutput() {
        let raw = "what the fuck do we mean by we needed a button"
        let out = "What the fuck do we mean by we needed a button?"
        #expect(VerbatimWordGuard.restore(raw: raw, output: out) == out)
    }

    // MARK: Never disturbs ordinary cleanup

    @Test("a transcript with no strong language is returned unchanged")
    func passesThroughCleanTranscript() {
        let raw = "so um if I want to filter the agents like can I do that"
        let out = "So if I want to filter the agents, can I do that?"
        #expect(VerbatimWordGuard.restore(raw: raw, output: out) == out)
    }

    /// The guard must not undo the cleanup the enhancement exists to do, even
    /// when strong language sits in the same sentence.
    @Test("filler removal beside strong language still stands")
    func keepsCleanupBesideStrongLanguage() {
        let raw = "why the fuck are we doing it like this and um adding attachments"
        let out = "Why the fuck are we doing it like this and adding attachments?"
        #expect(VerbatimWordGuard.restore(raw: raw, output: out) == out)
    }

    @Test("a self-correction collapse beside strong language is not reverted")
    func keepsSelfCorrectionCollapse() {
        let raw = "ship it on friday scratch that ship the damn thing on monday"
        let out = "Ship the damn thing on Monday."
        #expect(VerbatimWordGuard.restore(raw: raw, output: out) == out)
    }

    // MARK: Stem matching

    @Test("ambiguous stems are not protected", arguments: [
        "assessment", "hello", "classic", "grasshopper", "buttons",
    ])
    func doesNotProtectOrdinaryWords(_ word: String) {
        #expect(!VerbatimWordGuard.isProtected(word))
    }

    @Test("inflections of a protected stem are protected", arguments: [
        "fucked", "fucking", "shitty", "damned", "crappy", "pissed",
    ])
    func protectsInflections(_ word: String) {
        #expect(VerbatimWordGuard.isProtected(word))
    }

    @Test("trailing punctuation does not hide a protected word")
    func protectsDespitePunctuation() {
        #expect(VerbatimWordGuard.isProtected("fucked,"))
        #expect(VerbatimWordGuard.isProtected("\"shit\""))
    }
}
