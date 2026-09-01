import AppKit
import Testing
@testable import Sotto

/// Measures `PhoneticCorrectionService` against real mishears taken from the
/// history store's `EnhancementEditRecord` rows (corrections the user actually
/// made by hand) and from vocabulary terms that reached the pasted text
/// mangled. Only the word-level pairs are kept here — no dictation text.
///
/// The suite is a scoreboard, not a gate: `baseline` prints what the current
/// implementation recovers so a change to the gates can be measured rather
/// than argued. The `mustNotChange` cases ARE a gate — they are the failures
/// (`to`→`TUI`, `then`→`Thine`) that made the acoustic homophone unlock
/// unusable, and no widening may bring them back.
@Suite struct VocabularyCorrectionEvalTests {

    /// The user's live custom vocabulary, as the enhancement prompt receives it.
    static let vocabulary = [
        "Anthropic", "Apple Silicon", "Atlas", "Claude", "Claude Code", "Cloudflare",
        "cmux", "codex", "Control Plane", "Gemini", "HEIC", "Herdr", "Kunal", "Opus",
        "Parakeet", "Priyanshu", "siddhartha", "Sonnet", "Sotto", "SQLite",
        "SwiftData", "Tahoe", "Thine", "TUI", "Xcode",
    ]

    struct Case: Sendable, CustomStringConvertible {
        let heard: String
        let want: String
        let note: String
        var description: String { "\(heard) → \(want)" }
    }

    /// Mishears of a term that IS in the vocabulary. Every one of these reached
    /// the user's editor wrong; the first three were corrected by hand.
    static let shouldCorrect: [Case] = [
        Case(heard: "how do I run codecs in it then",
             want: "how do I run codex in it then",
             note: "real English word blocks the OOV gate"),
        Case(heard: "each window in Herder keeps scrolling",
             want: "each window in Herdr keeps scrolling",
             note: "real English word blocks the OOV gate"),
    ]

    /// Real mishears that phonetics cannot reach, kept so the boundary is
    /// explicit rather than forgotten. Both need an exact `WordReplacement`
    /// entry, not a wider phonetic gate — widening far enough to catch them
    /// also catches `cloud`→`Claude`.
    static let knownLimits: [Case] = [
        Case(heard: "reattach the hurdle pane",
             want: "reattach the Herdr pane",
             note: "keys differ (HRTL vs HRTR) and the mishear spans two words"),
        Case(heard: "convert it to HAC first",
             want: "convert it to HEIC first",
             note: "key HK is two characters — too short to be distinctive"),
    ]

    /// Load-bearing negatives. `to`→`TUI` and `then`→`Thine` are the exact
    /// rewrites that forced the acoustic unlock off; a widened gate that
    /// resurrects them is worse than no widening at all.
    static let mustNotChange: [Case] = [
        Case(heard: "send it to the server", want: "send it to the server",
             note: "to vs TUI — one-character phonetic key"),
        Case(heard: "then we start the run", want: "then we start the run",
             note: "then vs Thine — two-character phonetic key"),
        Case(heard: "cloud computing scales well", want: "cloud computing scales well",
             note: "cloud vs Claude — key collision, surface distance 2"),
        Case(heard: "the code is fine", want: "the code is fine",
             note: "code vs codex — common word, must not be pulled in"),
        Case(heard: "ask the counselor about it", want: "ask the counselor about it",
             note: "phonetic match outside any sane surface gate"),
        Case(heard: "open the file and read it", want: "open the file and read it",
             note: "ordinary prose stays untouched"),
    ]

    /// The OS spell checker is the real OOV oracle in the pipeline, so the eval
    /// uses it rather than a stub — a stub would hide exactly the gate that is
    /// under test (real English words are never flagged).
    private func osIsMisspelled(_ word: String) -> Bool {
        let range = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0)
        return range.location != NSNotFound && range.length > 0
    }

    @Test("recovers a mishear of a term that is in the vocabulary", arguments: shouldCorrect)
    func recoversVocabularyTerm(_ testCase: Case) {
        let out = PhoneticCorrectionService.shared.correct(
            testCase.heard, vocabulary: Self.vocabulary, isMisspelled: osIsMisspelled)
        #expect(out == testCase.want, "got \"\(out)\" — \(testCase.note)")
    }

    @Test("documented limits stay unfixed until a WordReplacement covers them",
          arguments: knownLimits)
    func knownLimitStillFails(_ testCase: Case) {
        let out = PhoneticCorrectionService.shared.correct(
            testCase.heard, vocabulary: Self.vocabulary, isMisspelled: osIsMisspelled)
        #expect(out != testCase.want, "now recoverable — promote it out of knownLimits (\(testCase.note))")
    }

    @Test("no widening may rewrite ordinary English", arguments: mustNotChange)
    func neverRewritesOrdinaryEnglish(_ testCase: Case) {
        let out = PhoneticCorrectionService.shared.correct(
            testCase.heard, vocabulary: Self.vocabulary, isMisspelled: osIsMisspelled)
        #expect(out == testCase.want, "\(testCase.note)")
    }

    /// Pins the key facts the gate is built on, so a change to
    /// `DoubleMetaphone` that would silently reopen `to`→`TUI` fails here
    /// instead of in dictation.
    @Test("the phonetic keys the homophone gate depends on")
    func gateInputsAreStable() {
        #expect(DoubleMetaphone.encode("codecs").primary == DoubleMetaphone.encode("codex").primary)
        #expect(DoubleMetaphone.encode("herder").primary == DoubleMetaphone.encode("herdr").primary)
        // Short keys are the collision risk the gate's length rule exists for.
        #expect(DoubleMetaphone.encode("to").primary.count < 3)
        #expect(DoubleMetaphone.encode("then").primary.count < 3)
        // Equal keys with a short shared prefix — blocked by the prefix rule.
        #expect(DoubleMetaphone.encode("cloud").primary == DoubleMetaphone.encode("claude").primary)
        #expect(!PhoneticCorrectionService.homophoneGatePasses(
            key: DoubleMetaphone.encode("cloud").primary, heard: "cloud", term: "claude"))
    }
}
