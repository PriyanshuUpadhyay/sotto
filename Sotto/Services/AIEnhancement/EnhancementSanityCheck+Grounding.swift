import Foundation

extension EnhancementSanityCheck {

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
    static func groundedFractionCheck(_ raw: String, _ out: String, _ vocabulary: Set<String>) -> (isLow: Bool, fraction: Double) {
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
}
