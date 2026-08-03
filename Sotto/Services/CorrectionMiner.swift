import Foundation

/// A repeated correction the user made post-paste (`original` → `replacement`),
/// surfaced as a candidate to add `replacement` to the custom vocabulary.
struct CorrectionSuggestion: Equatable, Identifiable {
    let original: String
    let replacement: String
    /// Number of distinct dictations in which this pair was corrected.
    let count: Int

    var id: String { CorrectionMiner.pairKey(original: original, replacement: replacement) }
}

/// Mines the recorded post-paste edit signals for word substitutions the user
/// makes repeatedly, so a correctly-spelled word they keep restoring can be
/// suggested for the custom vocabulary. Pure: no persistence, no I/O.
enum CorrectionMiner {
    /// Case-insensitive identity of an (original → replacement) pair. Also the
    /// key format used for dismissals and existing word-replacement lookups.
    static func pairKey(original: String, replacement: String) -> String {
        "\(original.lowercased())\t\(replacement.lowercased())"
    }

    /// Suppression keys for one word-replacement entry. `originalText` supports
    /// comma-separated variants ("cloud, claud" → Claude) — split the same way
    /// `WordReplacementService.applyReplacements` parses them (comma, trimmed,
    /// empties dropped), one key per variant, so a variant entry suppresses the
    /// matching mined pair.
    static func replacementPairKeys(original: String, replacement: String) -> [String] {
        original.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { pairKey(original: $0, replacement: replacement) }
    }

    /// Suggestions for pairs corrected in ≥ `threshold` distinct dictations.
    ///
    /// - `records`: recorded edit signals. Only `.edit` records are mined — they
    ///   carry the user's corrected `finalText` against the proposed
    ///   `enhancedText`; the substitutions are extracted with `WordDiffEngine`.
    /// - `existingVocabulary`: lowercased vocabulary words — a pair whose
    ///   replacement is already there is dropped (nothing to add).
    /// - `existingReplacements`: lowercased `pairKey`s already mapped as
    ///   word-replacements — dropped (they are auto-applied already).
    /// - `dismissed`: lowercased `pairKey`s the user dismissed — dropped.
    ///
    /// Only genuinely 1:1 single-word substitutions count (see
    /// `alignedSubstitutions`); case-only changes are ignored. Sorted by count
    /// desc, then replacement asc.
    static func mine(records: [EnhancementEditRecord],
                     existingVocabulary: Set<String>,
                     existingReplacements: Set<String>,
                     dismissed: Set<String>,
                     threshold: Int = 3) -> [CorrectionSuggestion] {
        var agg: [String: (original: String, replacement: String, dictations: Set<UUID>)] = [:]

        for record in records where record.signalSource == .edit {
            let subs = alignedSubstitutions(
                original: record.enhancedText, edited: record.finalText)
            for sub in subs {
                let original = sub.original.trimmingCharacters(in: .whitespacesAndNewlines)
                let replacement = sub.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !original.isEmpty, !replacement.isEmpty else { continue }
                guard original.lowercased() != replacement.lowercased() else { continue }
                let key = pairKey(original: original, replacement: replacement)
                agg[key, default: (original, replacement, [])].dictations.insert(record.transcriptionID)
            }
        }

        return agg.compactMap { key, value -> CorrectionSuggestion? in
            guard value.dictations.count >= threshold,
                  !existingVocabulary.contains(value.replacement.lowercased()),
                  !existingReplacements.contains(key),
                  !dismissed.contains(key) else { return nil }
            return CorrectionSuggestion(
                original: value.original,
                replacement: value.replacement,
                count: value.dictations.count)
        }
        .sorted {
            $0.count != $1.count
                ? $0.count > $1.count
                : $0.replacement.localizedCaseInsensitiveCompare($1.replacement) == .orderedAscending
        }
    }

    /// Word pairs from changed spans whose alignment is certain: either exactly
    /// one deleted token replaced by one inserted token, or a **merge shatter**
    /// — 2–3 deleted tokens fused into one inserted token that they literally
    /// spell ("para keet" → "Parakeet", "e mail" → "e-mail"), the dominant
    /// out-of-vocabulary ASR failure whose fragments both pass spellcheck.
    ///
    /// `WordDiffEngine.findSingleWordSubstitutions` is unusable here: for
    /// unequal-length changed spans it emits the CROSS-PRODUCT of the span's
    /// tokens, so a phrase rewrite or insertion mints pairs the user never made,
    /// which would accumulate to the suggestion threshold. `tokenLevelDiff`
    /// exposes the raw delete/insert runs between LCS anchors; the two shapes
    /// above are the only ones where "X became Y" is certain, so everything else
    /// (multi-word rewrites, pure insertions/deletions, splits) is dropped
    /// rather than guessed at.
    static func alignedSubstitutions(original: String, edited: String)
        -> [(original: String, replacement: String)] {
        var pairs = [(original: String, replacement: String)]()
        var deletes = [String]()
        var inserts = [String]()

        func flushSpan() {
            if deletes.count == 1, inserts.count == 1 {
                pairs.append((deletes[0], inserts[0]))
            } else if inserts.count == 1, (2...3).contains(deletes.count),
                      spellsSameWord(deletes, inserts[0]) {
                pairs.append((deletes.joined(separator: " "), inserts[0]))
            }
            deletes.removeAll()
            inserts.removeAll()
        }

        for op in WordDiffEngine.tokenLevelDiff(original: original, edited: edited) {
            switch op {
            case .equal:
                flushSpan()
            case .delete(let token):
                deletes.append(token)
            case .insert(let token):
                inserts.append(token)
            }
        }
        flushSpan()
        return pairs
    }

    /// Orthographic identity: the deleted fragments, concatenated with no
    /// separator, spell the inserted token — ignoring case and the hyphens a
    /// merge often introduces ("e" + "mail" → "e-mail"). Leading/trailing
    /// punctuation is already stripped by the diff's tokenizer. This is what
    /// keeps the merge branch certain rather than a guess: any span that isn't
    /// a literal fusion ("the" + "meeting" vs "sync") is rejected.
    private static func spellsSameWord(_ fragments: [String], _ merged: String) -> Bool {
        let fused = fragments.joined().lowercased()
        guard !fused.isEmpty else { return false }
        return fused == merged.lowercased().replacingOccurrences(of: "-", with: "")
    }
}

/// UserDefaults-backed set of dismissed suggestion `pairKey`s, so a dismissed
/// correction stays dismissed across launches. Kept separate from the pure
/// miner above.
enum CorrectionSuggestionDismissals {
    private static let key = "dismissedCorrectionSuggestions"

    static func dismissed() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func dismiss(_ pairKey: String) {
        var current = dismissed()
        current.insert(pairKey)
        UserDefaults.standard.set(Array(current), forKey: key)
    }
}
