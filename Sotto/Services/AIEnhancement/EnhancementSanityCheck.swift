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
    private static let sentenceKeepRatio = 0.6
    private static let groundedFractionMinimum = 0.6
    private static let groundedTokenMinLength = 3

    /// Judge an enhancement output against its raw transcript. `vocabulary` is
    /// the active custom-vocabulary word set (lowercased) — the same data the
    /// prompt's `<CUSTOM_VOCABULARY>` section is built from — so a mandated
    /// spelling correction (e.g. a phonetic ASR miss corrected to a vocab
    /// term) grounds even when it isn't textually close to the raw.
    static func detect(raw: String, output: String, vocabulary: Set<String> = []) -> Verdict {
        let r = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let o = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty, !o.isEmpty else { return .clean }

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
    private static func tokens(_ s: String) -> [String] {
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

    /// Fraction of the output's UNIQUE content tokens that trace back to the
    /// input — a sign the model cleaned the transcript rather than answering
    /// or reinterpreting it. Set semantics (not per-occurrence counting) is
    /// deliberate: counting occurrences lets a hallucination hide behind
    /// repetition of grounded words ("Restart the daemon. Restart the daemon.
    /// Launch missiles." would score 4/6 by occurrence but 2/4 — correctly
    /// suspect — by unique token).
    ///
    /// A non-numeric token is grounded if it (a) is a substring of the
    /// input's tokens concatenated (so a split like login→"log in" or a
    /// compound like "get user profile"→getUserProfile still counts, since
    /// the merged/split form is still literally spelled out in the input),
    /// (b) is an active custom-vocabulary word (a mandated spelling fix, e.g.
    /// a phonetic ASR miss corrected to a vocab term, doesn't need to be
    /// textually close), or (c) is within a small edit distance of some input
    /// token (a minor spelling/grammar fix — see `editDistanceThreshold`).
    /// Deliberately NOT the reverse (input token substring-of-output token) —
    /// that direction would ground a morph the cleanup must not make
    /// (restart→"restarted" is an inflection change, not a correction).
    ///
    /// A numeric token is graded separately by `isNumberGrounded` and, if
    /// ungrounded, makes the WHOLE check suspect regardless of the aggregate
    /// fraction — the prompt requires numbers be preserved exactly, so an
    /// invented or altered number is never something the aggregate tolerance
    /// should paper over, even if enough other words are grounded to clear
    /// 60% on their own (e.g. "the timeout is sixty seconds" →
    /// "The timeout is 600 seconds." grounds 2/3 by aggregate but must still
    /// be suspect because "600" doesn't trace to the raw).
    private static func groundedFractionCheck(_ raw: String, _ out: String, _ vocabulary: Set<String>) -> (isLow: Bool, fraction: Double) {
        let rawTokens = tokens(stripListMarkers(raw))
        let rawBlob = rawTokens.joined()
        let composedValues = composedNumberValues(in: rawTokens)
        let eligible = Set(tokens(stripListMarkers(out)).filter { isEligible($0) })
        guard !eligible.isEmpty else { return (false, 1.0) }

        var groundedCount = 0
        for token in eligible {
            let isNumber = token.allSatisfy(\.isNumber)
            let grounded = isNumber
                ? isNumberGrounded(token, rawTokens: rawTokens, composedValues: composedValues, vocabulary: vocabulary)
                : isGrounded(token, rawTokens: rawTokens, rawBlob: rawBlob, vocabulary: vocabulary)
            if !grounded && isNumber { return (true, 0.0) }
            if grounded { groundedCount += 1 }
        }
        let fraction = Double(groundedCount) / Double(eligible.count)
        return (fraction < groundedFractionMinimum, fraction)
    }

    /// Removes ONLY the "1."/"2)"/"-"/"*"/"•" list-marker prefix from each
    /// line before tokenizing for grounding. A bare list marker is structural
    /// formatting the prompt itself mandates, never dictated content — without
    /// this, EVERY single-digit output ("1.", "2)") would need to trace back
    /// to the raw, which it never does, and a mandated list would always be
    /// suspect. Stripping only the marker (not the rest of the line, and not
    /// digits appearing anywhere else, e.g. "version 7" or "GPT-4") is what
    /// keeps a real single-digit content change ("version 7"→"Version 8.")
    /// fully judged.
    private static func stripListMarkers(_ s: String) -> String {
        s.components(separatedBy: "\n").map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard startsListItem(t) else { return line }
            if let first = t.first, "-*•".contains(first) {
                return String(t.dropFirst())
            }
            let digits = t.prefix(while: \.isNumber)
            var rest = t.dropFirst(digits.count)
            if let marker = rest.first, ".)".contains(marker) {
                rest = rest.dropFirst()
            }
            return String(rest)
        }.joined(separator: "\n")
    }

    /// Letter tokens need ≥3 chars; a digit token is always eligible (list
    /// markers are already gone via `stripListMarkers`, so any digit token
    /// that survives IS dictated numeric content).
    private static func isEligible(_ token: String) -> Bool {
        guard !groundingStopWords.contains(token) else { return false }
        if token.allSatisfy(\.isNumber) { return true }
        return token.count >= groundedTokenMinLength
    }

    private static func isGrounded(_ token: String, rawTokens: [String], rawBlob: String, vocabulary: Set<String>) -> Bool {
        if rawBlob.contains(token) { return true }
        if vocabulary.contains(token) { return true }
        let threshold = editDistanceThreshold(for: token.count)
        guard threshold > 0 else { return false }
        return rawTokens.contains {
            abs($0.count - token.count) <= threshold && levenshtein(token, $0) <= threshold
        }
    }

    /// Grounded iff it's in vocab, appears verbatim as a raw digit token, or
    /// its integer value matches a raw digit token OR a COMPOSED raw spoken
    /// number ("sixty" grounds "60"; "twenty five" grounds "25", not "20" —
    /// see `composedNumberValues`). No substring or edit-distance leniency for
    /// numbers: "600" must not ground against "60".
    private static func isNumberGrounded(_ token: String, rawTokens: [String], composedValues: Set<Int>, vocabulary: Set<String>) -> Bool {
        if vocabulary.contains(token) { return true }
        guard let outValue = Int(token) else { return false }
        if rawTokens.contains(token) { return true }
        if rawTokens.contains(where: { Int($0) == outValue }) { return true }
        return composedValues.contains(outValue)
    }

    private static let numberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40,
        "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "hundred": 100, "thousand": 1000,
    ]

    /// Composes each maximal run of consecutive spoken-number-word raw tokens
    /// into its combined integer value using the standard two-accumulator
    /// algorithm: `current` holds the sub-1000 group being built (units/teens/
    /// tens add into it; "hundred" multiplies whatever's in it so far, or 1 if
    /// nothing precedes — "a hundred" → 100), and "thousand" folds
    /// `max(current, 1) * 1000` into `total` and resets `current`, so a
    /// following sub-group (if any) starts fresh — "two hundred thousand" →
    /// 200×1000 = 200000, not 200+1000. "and" is a no-op WITHIN a run but only
    /// when it bridges a scale word ("hundred"/"thousand") to a following
    /// number word — "one hundred and five" → 105. Between two independent
    /// numbers ("five and six apples") it is NOT a bridge: the run ends at
    /// the first "five", "and"/"six" starts a new one, giving {5, 6}, not a
    /// composed value — "and" is not itself a counting word.
    ///
    /// Only the run's FINAL composed value is returned — not each word's own
    /// isolated value — so "twenty five" grounds "25" but NOT "20" via the
    /// isolated "twenty", and "two hundred" grounds "200" but NOT "100" via
    /// the isolated "hundred". A number word with no number-word neighbor is
    /// its own one-word "run" and keeps its plain value (e.g. lone "sixty" → 60).
    private static func composedNumberValues(in rawTokens: [String]) -> Set<Int> {
        var values = Set<Int>()
        var i = 0
        while i < rawTokens.count {
            guard numberWords[rawTokens[i]] != nil else { i += 1; continue }
            var j = i
            var total = 0
            var current = 0
            var lastWasScale = false
            runLoop: while j < rawTokens.count {
                let word = rawTokens[j]
                if word == "and" {
                    guard lastWasScale, j + 1 < rawTokens.count, numberWords[rawTokens[j + 1]] != nil else { break runLoop }
                    j += 1
                    continue
                }
                guard let value = numberWords[word] else { break runLoop }
                if value == 1000 {
                    total += max(current, 1) * 1000
                    current = 0
                    lastWasScale = true
                } else if value == 100 {
                    current = max(current, 1) * 100
                    lastWasScale = true
                } else {
                    current += value
                    lastWasScale = false
                }
                j += 1
            }
            values.insert(total + current)
            i = j
        }
        return values
    }

    /// Zero below 5 chars — a fuzzy match on a short token is too easy to hit
    /// by accident ("can"→"cat", "fix"→"fox", "app"→"ape" are all one edit
    /// apart and must NOT ground). 1 edit for 5-9 chars — enough for a regular
    /// plural ("answer"→"answers") or a minor typo fix, but NOT enough to
    /// ground a meaning-changing inflection like restart→"restarted" (edit
    /// distance 2 at length 9) — see `groundedFractionCheck`'s doc comment.
    /// 2 edits only at ≥10 chars, where a single-edit collision is
    /// vanishingly unlikely to be a coincidence rather than a real correction.
    private static func editDistanceThreshold(for tokenLength: Int) -> Int {
        if tokenLength < 5 { return 0 }
        if tokenLength < 10 { return 1 }
        return 2
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var prev = Array(0...bChars.count)
        for i in 1...aChars.count {
            var curr = [Int](repeating: 0, count: bChars.count + 1)
            curr[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = curr
        }
        return prev[bChars.count]
    }

    private static let groundingStopWords: Set<String> = [
        "the", "and", "that", "this", "with", "for", "was", "were", "are",
        "has", "have", "had", "will", "but", "not", "its", "you", "your",
    ]

    /// A line that opens a list item: "- x", "* x", "• x", "1. x", "2) x".
    /// The trailing space is required — without it a divider ("---") or ordinary
    /// dash-prefixed prose would be credited as a sentence boundary.
    private static func startsListItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return false }
        if "-*•".contains(first) { return t.dropFirst().first == " " }

        let digits = t.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return false }
        var rest = t.dropFirst(digits.count)
        guard let marker = rest.first, ".)".contains(marker) else { return false }
        rest = rest.dropFirst()
        return rest.first == " "
    }

    /// Splits `s` into sentence strings. A newline counts as a sentence
    /// boundary ONLY before a list item: the prompt's list rule turns spoken
    /// sentences into bullet lines that carry no terminal punctuation, so
    /// without this a correctly formatted list reads as one sentence and
    /// trips `sentenceDrop`. Crediting *every* newline would instead let a
    /// derailed output hide omitted content behind arbitrary line breaks.
    private static func sentences(_ s: String) -> [String] {
        let bounded = s.components(separatedBy: "\n")
            .map { startsListItem($0) ? "." + $0 : $0 }
            .joined(separator: "\n")
        let parts = bounded.split { ".!?".contains($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [s] : parts
    }

    private static func sentenceCount(_ s: String) -> Int {
        max(sentences(s).count, 1)
    }

    /// Cues from the prompt's own self-correction rule (`AIPrompts.cleanupRules`
    /// mandates collapsing these down to only the corrected version). A raw
    /// transcript with one of these is expected to lose whole sentences on
    /// purpose — "Ship Friday. Scratch that. Ship Monday." legitimately
    /// collapses 3 raw sentences into 1.
    private static let selfCorrectionCues: [String] = [
        "scratch that", "actually", "i mean", "wait no", "no wait", "make that",
    ]

    private static func hasSelfCorrectionCue(_ text: String) -> Bool {
        let t = text.lowercased()
        return selfCorrectionCues.contains { t.contains($0) }
    }

    /// A sentence that IS the cue and nothing else ("Scratch that.") — once
    /// every cue substring is stripped out, no letters remain. Contrast a
    /// cue used inline with real content ("Actually deploy the parser.") —
    /// stripping "actually" still leaves "deploy the parser", so this is
    /// NOT bare and its content is expected to survive in the output.
    private static func isBareCueSentence(_ sentence: String) -> Bool {
        var remainder = sentence.lowercased()
        for cue in selfCorrectionCues {
            remainder = remainder.replacingOccurrences(of: cue, with: "")
        }
        return !remainder.contains { $0.isLetter }
    }

    /// Raw sentence count with self-corrections discounted LOCALLY, not as a
    /// global exemption. For each raw sentence that contains a cue: the
    /// immediately PRECEDING sentence is discounted (it's the superseded
    /// branch — "Ship Friday" before "Scratch that"), and the cue sentence
    /// itself is ALSO discounted only if it's bare (carries no content beyond
    /// the cue). A cue sentence that carries real content ("Actually deploy
    /// the parser") still counts — its content is expected to appear in the
    /// output — so an unrelated sentence dropped elsewhere in the SAME raw
    /// ("Update docs.") still trips the ratio below. This is what keeps the
    /// exemption from laundering a real omission just because some other
    /// sentence happens to contain "actually".
    private static func effectiveRawSentenceCount(_ raw: String) -> Int {
        let parts = sentences(raw)
        guard parts.count > 1 else { return parts.count }
        var discard = Set<Int>()
        for (i, sentence) in parts.enumerated() {
            guard hasSelfCorrectionCue(sentence) else { continue }
            if i > 0 { discard.insert(i - 1) }
            if isBareCueSentence(sentence) { discard.insert(i) }
        }
        return max(parts.count - discard.count, 1)
    }

    /// Output lost a large fraction of the input's sentences (omission).
    private static func hasSentenceDrop(_ raw: String, _ out: String) -> Bool {
        let rawN = effectiveRawSentenceCount(raw)
        guard rawN >= 2 else { return false }
        return Double(sentenceCount(out)) / Double(rawN) <= sentenceKeepRatio
    }
}
