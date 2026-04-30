import Foundation

/// W12.D voice-trigger detection. Suffix-match policy: lowercase the input,
/// strip trailing punctuation, exact-suffix-match against the configured
/// trigger list with a leading word-boundary check (start-of-string OR
/// whitespace) so "transcend it" doesn't fire "send it". On match: return
/// cleaned text + the AutoSendKey to fire after paste. See plan
/// `docs/superpowers/plans/W12D-hands-free-vad.md` §Migration policy #7.
enum VoiceTriggerFilter {
    struct TriggerHit: Equatable {
        let cleanedText: String
        let autoSend: AutoSendKey
        let matchedPhrase: String
    }

    static func detectTrigger(in text: String, against phrases: [String]) -> TriggerHit? {
        guard !phrases.isEmpty else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Strip trailing punctuation for comparison.
        let trailingPunct = CharacterSet(charactersIn: ".,!?;:\"'`)]}")
        let stripped = trimmingTrailingCharactersInSet(trimmed, set: trailingPunct)
        let strippedLower = stripped.lowercased()

        for phrase in phrases.map({ $0.lowercased() }) {
            let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPhrase.isEmpty else { continue }

            if strippedLower.hasSuffix(trimmedPhrase) {
                let cutoff = strippedLower.count - trimmedPhrase.count
                let isAtStart = cutoff == 0

                // Word-boundary check: the char immediately before the suffix
                // must be whitespace; otherwise we'd match "transcend it".
                if !isAtStart {
                    let beforeIndex = strippedLower.index(strippedLower.startIndex, offsetBy: cutoff)
                    let priorChar = strippedLower[strippedLower.index(before: beforeIndex)]
                    guard priorChar.isWhitespace else { continue }
                }

                // Strip the trigger from the original case-preserving text.
                // ASCII length parity assumption: `lowercased()` doesn't
                // change length for the latin-1 subset of the default phrase
                // list.
                let strippedCutoff = stripped.index(stripped.startIndex, offsetBy: cutoff)
                var cleaned = String(stripped[..<strippedCutoff])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Restore a sentence-ending period if the original ended with
                // one — the trigger may have absorbed it.
                if let lastChar = trimmed.last, ".!?".contains(lastChar) {
                    if let cleanedLast = cleaned.last, !".!?".contains(cleanedLast) {
                        cleaned.append(".")
                    } else if cleaned.isEmpty {
                        // Whole utterance was just the trigger — leave empty.
                    }
                }
                return TriggerHit(
                    cleanedText: cleaned,
                    autoSend: .enter,
                    matchedPhrase: trimmedPhrase
                )
            }
        }
        return nil
    }

    private static func trimmingTrailingCharactersInSet(_ s: String, set: CharacterSet) -> String {
        var out = s
        while let last = out.unicodeScalars.last, set.contains(last) {
            out.removeLast()
        }
        return out
    }
}
