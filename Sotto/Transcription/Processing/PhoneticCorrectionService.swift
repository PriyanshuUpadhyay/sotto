import Foundation
import AppKit
import SwiftData

/// Deterministic phonetic post-correction: rewrites OOV (out-of-vocabulary)
/// ASR mishears to the user's canonical custom-vocabulary spelling, gated on
/// phonetic-key equality + a tight surface Levenshtein distance so legitimate
/// English words are never touched. Runs in the transcription pipeline right
/// after the exact-match `WordReplacementService`.
///
/// v1 limitation: single-token correction only. Multi-word vocab terms
/// ("subagent driven development") and multi-token mishears ("subvision
/// development") are out of scope.
final class PhoneticCorrectionService {
    static let shared = PhoneticCorrectionService()
    private init() {}

    /// Pure core: vocabulary + OOV predicate are injected so this is testable
    /// without AppKit or SwiftData.
    /// - Parameter acousticallyConfirmed: when non-nil (the opt-in CTC boosting
    ///   path), corrections are restricted to terms the spotter confirmed were
    ///   spoken, AND a valid (non-OOV) word may be rewritten toward a confirmed
    ///   term — the homophone unlock. When nil, behavior is unchanged: OOV-gated
    ///   correction with no acoustic restriction.
    func correct(_ text: String, vocabulary: [String], isMisspelled: (String) -> Bool,
                 acousticallyConfirmed: Set<String>? = nil) -> String {
        correctDetailed(text, vocabulary: vocabulary, isMisspelled: isMisspelled,
                        acousticallyConfirmed: acousticallyConfirmed).text
    }

    /// Detail-returning core: same correction logic as `correct`, but also
    /// reports each chosen replacement so the pipeline trace can surface which
    /// token changed, from→to, why, and the Levenshtein distance.
    func correctDetailed(_ text: String, vocabulary: [String], isMisspelled: (String) -> Bool,
                         acousticallyConfirmed: Set<String>? = nil)
        -> (text: String, corrections: [TranscriptionTrace.PhoneticCorrection]) {
        guard !vocabulary.isEmpty else { return (text, []) }

        let entries: [(term: String, key: String, lower: String)] = vocabulary.compactMap { term in
            let key = DoubleMetaphone.encode(term).primary
            guard !key.isEmpty else { return nil }
            return (term, key, term.lowercased())
        }
        guard !entries.isEmpty else { return (text, []) }

        // Split on spaces, preserving runs (so the output spacing is unchanged).
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var corrections: [TranscriptionTrace.PhoneticCorrection] = []
        let corrected = tokens.map { token -> String in
            let (out, correction) = correctToken(token, entries: entries,
                                                 isMisspelled: isMisspelled, confirmed: acousticallyConfirmed)
            if let correction { corrections.append(correction) }
            return out
        }
        return (corrected.joined(separator: " "), corrections)
    }

    /// Pipeline convenience: fetches the live vocabulary and uses the OS spell
    /// checker for the OOV gate.
    func correct(_ text: String, using context: ModelContext,
                 acousticallyConfirmed: Set<String>? = nil) -> String {
        correctDetailed(text, using: context, acousticallyConfirmed: acousticallyConfirmed).text
    }

    /// Detail-returning pipeline convenience — drives `correctDetailed` with the
    /// live vocabulary and OS spell checker.
    func correctDetailed(_ text: String, using context: ModelContext,
                         acousticallyConfirmed: Set<String>? = nil)
        -> (text: String, corrections: [TranscriptionTrace.PhoneticCorrection]) {
        let vocabulary = (try? context.fetch(FetchDescriptor<VocabularyWord>()))?.map { $0.word } ?? []
        return correctDetailed(text, vocabulary: vocabulary, isMisspelled: osIsMisspelled,
                               acousticallyConfirmed: acousticallyConfirmed)
    }

    private func correctToken(
        _ token: String,
        entries: [(term: String, key: String, lower: String)],
        isMisspelled: (String) -> Bool,
        confirmed: Set<String>?
    ) -> (String, TranscriptionTrace.PhoneticCorrection?) {
        // Peel leading/trailing punctuation, keep the alphanumeric core.
        let chars = Array(token)
        var start = 0
        var end = chars.count
        while start < end && !chars[start].isLetter && !chars[start].isNumber { start += 1 }
        while end > start && !chars[end - 1].isLetter && !chars[end - 1].isNumber { end -= 1 }
        guard start < end else { return (token, nil) }

        let lead = String(chars[0..<start])
        let core = String(chars[start..<end])
        let trail = String(chars[end..<chars.count])
        let coreLower = core.lowercased()

        // Already an exact vocab term → not a candidate.
        if entries.contains(where: { $0.lower == coreLower }) { return (token, nil) }
        // OOV gate: check the lowercased core, since ASR often emits short
        // domain terms ALL-CAPS ("CMAX") and NSSpellChecker treats all-caps
        // tokens as acronyms and never flags them.
        //
        // A valid (non-OOV) word is still a candidate, but only through the
        // much stricter `homophoneGatePasses` below. The most common mishear
        // of a vocabulary term is an ordinary English word that sounds like it
        // ("Herdr" heard as "herder", "codex" as "codecs"), so an OOV-only
        // gate misses exactly the cases the vocabulary exists to fix.
        let isOOV = isMisspelled(coreLower)

        let coreKey = DoubleMetaphone.encode(core).primary
        guard !coreKey.isEmpty else { return (token, nil) }

        var best: (term: String, dist: Int)?
        for entry in entries where entry.key == coreKey {
            // Acoustic gate: restrict corrections to confirmed terms when boosting is on.
            if let confirmed, !confirmed.contains(entry.lower) { continue }
            let dist = levenshtein(coreLower, entry.lower)
            // Hard anchor: an acoustically-confirmed term is strong evidence the
            // word was spoken, so it widens the surface Levenshtein gate
            // (max(2, count/2)) vs the conservative OOV-only gate (max(1, count/4)).
            // When `confirmed` is non-nil, every entry that reaches here is
            // confirmed (the filter above drops the rest), so the wider gate
            // applies only to acoustically-anchored corrections.
            let gate: Int
            if confirmed != nil {
                gate = max(2, entry.term.count / 2)
            } else if isOOV {
                gate = max(1, entry.term.count / 4)
            } else {
                // The homophone gate below carries the safety here, so the
                // surface distance only has to admit a one- or two-character
                // mishear ("codecs"/"codex" is 2).
                gate = 2
            }
            guard dist <= gate else { continue }
            if confirmed == nil, !isOOV,
               !Self.homophoneGatePasses(key: coreKey, heard: coreLower, term: entry.lower) { continue }
            if best == nil || dist < best!.dist
                || (dist == best!.dist && entry.term.count < best!.term.count) {
                best = (entry.term, dist)
            }
        }
        guard let best else { return (token, nil) }

        // Preserve a leading capital (e.g. sentence-start "Cmax" → "Cmux").
        let replacement: String
        if let first = core.first, first.isUppercase {
            replacement = best.term.prefix(1).uppercased() + best.term.dropFirst()
        } else {
            replacement = best.term
        }
        let reason = isOOV ? "oov" : "homophone-unlock"
        let correction = TranscriptionTrace.PhoneticCorrection(
            token: token, from: core, to: replacement, reason: reason, distance: best.dist)
        return (lead + replacement + trail, correction)
    }

    /// Whether a valid English word may be rewritten to a vocabulary term that
    /// shares its phonetic key. Equal keys alone are far too weak: `to`/`TUI`
    /// and `then`/`Thine` collide, and rewriting those is what forced the
    /// earlier acoustic unlock off. Two extra conditions separate a real
    /// mishear from a collision, and both are needed:
    ///
    /// - a distinctive key (≥ 3 characters), which drops the `T` and `0N`
    ///   collisions that pull in the shortest, most common words;
    /// - a long shared prefix (≥ 4 characters), which drops `cloud`/`Claude`
    ///   (shares only `cl`) while keeping `codecs`/`codex` and `herder`/`Herdr`
    ///   (both share 4).
    static func homophoneGatePasses(key: String, heard: String, term: String) -> Bool {
        guard key.count >= 3 else { return false }
        return sharedPrefixLength(heard, term) >= 4
    }

    private static func sharedPrefixLength(_ a: String, _ b: String) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }

    private func osIsMisspelled(_ word: String) -> Bool {
        let range = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0)
        return range.location != NSNotFound && range.length > 0
    }
}

private func levenshtein(_ a: String, _ b: String) -> Int {
    let s = Array(a), t = Array(b)
    if s.isEmpty { return t.count }
    if t.isEmpty { return s.count }
    var prev = Array(0...t.count)
    var curr = [Int](repeating: 0, count: t.count + 1)
    for i in 1...s.count {
        curr[0] = i
        for j in 1...t.count {
            let cost = s[i - 1] == t[j - 1] ? 0 : 1
            curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &curr)
    }
    return prev[t.count]
}
