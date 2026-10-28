import Foundation

/// Heuristic post-check for the AI-enhancement step. Flags an output that
/// reads like an *answer to* the dictation rather than a *cleanup of* it —
/// the dominant on-device failure mode (see spec
/// `2026-05-22-enhancement-quality-fix-design.md`). Pure, no dependencies.
enum EnhancementSanityCheck {

    enum Reason: String, CaseIterable {
        case personFlip           // first-person dictation rewritten into second person
        case answerOpener         // output begins with an answer phrase ("Yes, you can…")
        case metaPreamble         // output begins with a meta/answer preamble ("Reasoning:", "The request…")
        case lowGroundedFraction  // too few output content words trace back to the input
        case sentenceDrop         // output lost a large fraction of the input's sentences
    }

    enum Verdict: Equatable {
        case clean
        case suspect([Reason])
        var isSuspect: Bool { if case .suspect = self { return true } else { return false } }
        var isClean: Bool   { if case .clean   = self { return true } else { return false } }
    }

    // First-draft thresholds — tune against the replay harness (Task 8).
    static let sentenceKeepRatio = 0.6
    static let groundedFractionMinimum = 0.6
    static let groundedTokenMinLength = 3

    /// Judge an enhancement output against its raw transcript. `vocabulary` is
    /// the active custom-vocabulary word set (lowercased) — the same data the
    /// prompt's `<CUSTOM_VOCABULARY>` section is built from — so a mandated
    /// spelling correction (e.g. a phonetic ASR miss corrected to a vocab
    /// term) grounds even when it isn't textually close to the raw.
    static func detect(raw: String, output: String, vocabulary: Set<String> = []) -> Verdict {
        let r = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let o = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty else { return .clean }
        // An empty output for non-empty input is total sentence loss, not a
        // clean pass. Two production calls returned "" and the pipeline pasted
        // it over the dictation (2026-09-16, gguf-s1-mini). Reporting it
        // .suspect routes it into the hardened retry and then
        // `deterministicCleanup`, so the user gets cleaned raw text, never
        // nothing. Guards every provider, not only the one that was seen to
        // fail.
        guard !o.isEmpty else { return .suspect([.sentenceDrop]) }

        var reasons: [Reason] = []
        if hasPersonFlip(r, o)   { reasons.append(.personFlip) }
        if hasAnswerOpener(r, o) { reasons.append(.answerOpener) }
        if hasMetaPreamble(r, o) { reasons.append(.metaPreamble) }
        if groundedFractionCheck(r, o, vocabulary).isLow { reasons.append(.lowGroundedFraction) }
        if hasSentenceDrop(r, o) { reasons.append(.sentenceDrop) }
        return reasons.isEmpty ? .clean : .suspect(reasons)
    }

    /// True when the raw transcript already reads clean — `deterministicCleanup`
    /// would not change it AND it ends with terminal punctuation. Used to skip
    /// the LLM enhance step entirely when it would be a no-op (~66% of runs).
    /// Empty input is never "clean" (nothing to skip).
    static func isLikelyClean(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let last = trimmed.last, ".!?".contains(last) else { return false }
        let cleaned = deterministicCleanup(trimmed)
        return EditTextNormalizer.normalize(cleaned) == EditTextNormalizer.normalize(trimmed)
    }

    /// Whether the enhance step should call the model at all. The skip is
    /// opt-in: with `skipWhenClean` off — the shipped default — every
    /// transcript goes to the model, clean or not.
    static func shouldCallModel(_ raw: String, skipWhenClean: Bool) -> Bool {
        !(skipWhenClean && isLikelyClean(raw))
    }

    /// Model-free last-resort cleanup of the raw transcript: the shared
    /// `TranscriptPrepass` (whitespace, standalone fillers, immediately
    /// repeated words and phrases) plus the two things only this path needs —
    /// a capitalized first letter and terminal punctuation. Never reorders,
    /// never paraphrases — so it can never produce an answer. Used by the
    /// runtime repair guard (Task 4) when the LLM output is rejected twice.
    static func deterministicCleanup(_ raw: String) -> String {
        var s = TranscriptPrepass.clean(raw)
        guard !s.isEmpty else { return "" }

        s.replaceSubrange(s.startIndex...s.startIndex, with: String(s[s.startIndex]).uppercased())
        if let last = s.last, !".!?".contains(last) { s.append(".") }
        return s
    }

    // MARK: - Tokenization

    /// Lowercased letter-runs and digit-runs. Splitting on every character
    /// that's neither turns "we'll" into ["we","ll"] and "I'm" into ["i","m"],
    /// so the pronoun survives as its own token, while a digit run like "60"
    /// survives as its own numeric token (grounding needs it — see
    /// `groundedFractionCheck`). Punctuation is dropped; a mixed run like
    /// "swift3" stays one token, which is fine since nothing here expects that
    /// shape from real dictation.
    static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init).filter { !$0.isEmpty }
    }

    // MARK: - Heuristics

    private static let firstPerson: Set<String> =
        ["i", "we", "my", "me", "mine", "myself", "our", "ours", "us"]
    private static let secondPerson: Set<String> =
        ["you", "your", "yours", "yourself"]

    /// Speaker was clearly first-person; the output erased it for second person.
    private static func hasPersonFlip(_ raw: String, _ out: String) -> Bool {
        let r = tokens(raw), o = tokens(out)
        let rawFirst = r.filter(firstPerson.contains).count
        let outFirst = o.filter(firstPerson.contains).count
        let rawSecond = r.filter(secondPerson.contains).count
        let outSecond = o.filter(secondPerson.contains).count
        return rawFirst >= 2 && outFirst == 0 && outSecond > rawSecond
    }

    private static let answerOpeners: [String] = [
        "yes ", "yes,", "no ", "no,", "sure", "certainly", "of course",
        "you can", "you could", "you should", "you will", "youll", "you may",
        "you would", "youd", "heres", "here is", "here are",
        "i recommend", "id recommend", "i can help", "to do this", "absolutely",
    ]

    /// First 24 chars, lowercased, apostrophes stripped — enough to spot an opener.
    private static func startSlice(_ s: String) -> String {
        let c = s.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(c.prefix(24))
    }

    /// Output starts with an answer phrase that the input did not.
    private static func hasAnswerOpener(_ raw: String, _ out: String) -> Bool {
        let outStart = startSlice(out)
        let rawStart = startSlice(raw)
        let outOpens = answerOpeners.contains { outStart.hasPrefix($0) }
        let rawOpens = answerOpeners.contains { rawStart.hasPrefix($0) }
        return outOpens && !rawOpens
    }

    /// Openers that signal the model wrote *about* the transcript (a meta /
    /// reasoning answer) instead of cleaning it — e.g. "Reasoning: The request
    /// asks for…". Calibrated against a stored failure where a short imperative
    /// ("Give reasoning and then reply.") produced a long meta-answer.
    private static let metaOpeners: [String] = [
        "reasoning:", "reasoning ", "the request", "the transcript",
        "the dictation", "the text", "it appears", "it seems", "based on",
        "i cannot", "im unable", "i am unable", "as an ai",
    ]

    /// Output begins with a meta/answer preamble that the input did not.
    private static func hasMetaPreamble(_ raw: String, _ out: String) -> Bool {
        let outStart = startSlice(out)
        let rawStart = startSlice(raw)
        let outOpens = metaOpeners.contains { outStart.hasPrefix($0) }
        let rawOpens = metaOpeners.contains { rawStart.hasPrefix($0) }
        return outOpens && !rawOpens
    }
}
