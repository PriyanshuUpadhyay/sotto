import Foundation

extension EnhancementSanityCheck {

    /// A line that opens a list item: "- x", "* x", "• x", "1. x", "2) x".
    /// The trailing space is required — without it a divider ("---") or ordinary
    /// dash-prefixed prose would be credited as a sentence boundary.
    static func startsListItem(_ line: String) -> Bool {
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
    static func hasSentenceDrop(_ raw: String, _ out: String) -> Bool {
        let rawN = effectiveRawSentenceCount(raw)
        guard rawN >= 2 else { return false }
        return Double(sentenceCount(out)) / Double(rawN) <= sentenceKeepRatio
    }

    // MARK: - lostSentence

    /// A raw sentence must have this many distinct content words to be judged.
    /// A shorter one ("This is alright.") looks the same as a filler sentence
    /// the prompt tells the model to remove.
    static let lostSentenceMinWords = 3
    /// Below this fraction of its content words in the output, a raw sentence
    /// counts as lost.
    static let lostSentenceCoverage = 0.5

    /// One raw sentence is gone from the output: fewer than half of its
    /// distinct content words appear there. `hasSentenceDrop` compares counts
    /// only, so a long output that silently drops one real paragraph passes
    /// it. Calibrated on 993 judged real recordings: this flagged 21 of the 60
    /// outputs that judges marked as dropping a point, and 0 of 648 that every
    /// judge graded clean.
    ///
    /// A sentence that has a self-correction cue, or that the next sentence
    /// corrects, is skipped, because the prompt asks for it to go. Each
    /// vocabulary term that the output adds may replace up to two misheard
    /// raw words ("cooper netties" -> "Kubernetes"), so those count as kept.
    static func hasLostSentence(_ raw: String, _ out: String, _ vocabulary: Set<String> = []) -> Bool {
        let outTokens = Set(tokens(out))
        let outBlob = tokens(out).joined()
        let addedTerms = outTokens.intersection(vocabulary).subtracting(tokens(raw)).count
        let parts = rawSentences(raw)
        for (index, sentence) in parts.enumerated() {
            if hasSelfCorrectionCue(sentence) { continue }
            if index + 1 < parts.count, hasSelfCorrectionCue(parts[index + 1]) { continue }
            let words = Set(tokens(sentence).filter(isCoverageWord))
            guard words.count >= lostSentenceMinWords else { continue }
            let found = words.filter { isKept($0, outTokens: outTokens, outBlob: outBlob) }.count
            let kept = min(words.count, found + 2 * addedTerms)
            if Double(kept) / Double(words.count) < lostSentenceCoverage { return true }
        }
        return false
    }

    /// Sentence ends are ".", "!" or "?" followed by whitespace, and line
    /// breaks. A dot inside a token ("NetworkClient.swift", "99.99") is not
    /// an end.
    private static func rawSentences(_ raw: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var previous: Character = " "
        for char in raw {
            if char.isNewline || (char.isWhitespace && ".!?".contains(previous)) {
                parts.append(current)
                current = ""
            } else {
                current.append(char)
            }
            previous = char
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// A content word has 4 or more letters and is not a common word that the
    /// model may drop or rephrase while it cleans. Numbers are judged by the
    /// grounding check instead, because the model rewrites "four" as "4".
    private static func isCoverageWord(_ token: String) -> Bool {
        token.count >= 4 && !token.allSatisfy(\.isNumber) && numberWords[token] == nil
            && !coverageStopWords.contains(token)
    }

    /// Kept if spelled out inside the output's tokens (a split or merged form
    /// still counts) or within a small edit distance of an output token.
    private static func isKept(_ word: String, outTokens: Set<String>, outBlob: String) -> Bool {
        if outBlob.contains(word) { return true }
        let threshold = editDistanceThreshold(for: word.count)
        guard threshold > 0 else { return false }
        return outTokens.contains {
            abs($0.count - word.count) <= threshold && levenshtein(word, $0) <= threshold
        }
    }

    private static let coverageStopWords: Set<String> = [
        "that", "this", "with", "were", "have", "will", "just", "like", "okay",
        "yeah", "also", "then", "what", "when", "which", "there", "their", "they",
        "them", "from", "into", "about", "would", "could", "should", "some",
        "something", "thing", "things", "really", "very", "maybe", "much", "more",
        "because", "think", "know", "want", "need", "going", "gonna",
    ]
}
