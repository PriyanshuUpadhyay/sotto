import Foundation

/// Repairs a streaming (agreement-based) Parakeet transcript against one batch
/// decode of the same recording. Streaming stays the base text: on 298 reference
/// dictations it scored 3.09% WER against 3.63% for the batch decode, so the
/// batch text only contributes what streaming demonstrably lacks — dropped
/// trailing words, and the vocabulary swaps the CTC rescorer makes on it.
/// Pure: no models, no I/O.
enum StreamingTranscriptRepair {
    /// Fewer tail words than this are left alone: a lone extra word is as likely
    /// a filler or a decoder artifact as real speech.
    static let minTailWords = 2
    /// Caps the damage if the batch decode hallucinates after the last word.
    static let maxTailWords = 12

    /// Appends the words the batch decode heard after the streaming transcript's
    /// last word. Measured 2026-10-05: streaming lost 2+ final words in 5 of 241
    /// dictations ("…it should be" + "really exact").
    ///
    /// Acts only when the last three streaming words align, in order and
    /// back to back, with three batch words, so a tail is never grafted onto an
    /// ending the two decodes disagree on. The aligned last word is taken from the
    /// batch text so its punctuation fits the appended words ("be." → "be really
    /// exact.").
    static func appendingDroppedTail(streaming: String, batch: String) -> String {
        let a = tokenRanges(streaming), b = tokens(batch)
        guard a.count >= 3, b.count > a.count else { return streaming }
        let matches = alignedIndices(from: a.map { key(String(streaming[$0])) }, to: b.map(key))
        guard let last = matches[a.count - 1],
              matches[a.count - 2] == last - 1,
              matches[a.count - 3] == last - 2 else { return streaming }
        let tail = b[(last + 1)...]
        guard (minTailWords...maxTailWords).contains(tail.count) else { return streaming }
        // Earlier text keeps its own whitespace (paragraph breaks included).
        return String(streaming[..<a[a.count - 1].lowerBound]) + ([b[last]] + tail).joined(separator: " ")
    }

    /// Applies rescorer swaps (`original` phrase → vocabulary term) to `text`.
    /// Each swap replaces the first not-yet-replaced occurrence of its phrase,
    /// matched case-insensitively on whole words; trailing punctuation of the
    /// phrase's last word is kept. A swap whose phrase is absent changes nothing,
    /// because the two decodes can differ there.
    static func applyingSwaps(_ swaps: [(original: String, replacement: String)], to text: String) -> String {
        let ranges = tokenRanges(text)
        let keys = ranges.map { key(String(text[$0])) }
        var used = Set<Int>()
        var edits: [(range: Range<String.Index>, replacement: String)] = []
        for swap in swaps {
            let phrase = tokens(swap.original).map(key)
            guard !phrase.isEmpty, !swap.replacement.isEmpty, phrase.count <= keys.count else { continue }
            let start = (0...(keys.count - phrase.count)).first { i in
                !(i..<(i + phrase.count)).contains(where: used.contains)
                    && Array(keys[i..<(i + phrase.count)]) == phrase
            }
            guard let start else { continue }
            let span = start..<(start + phrase.count)
            used.formUnion(span)
            let lastWord = text[ranges[span.upperBound - 1]]
            let trailing = String(lastWord.reversed().prefix { !isWordChar($0) }.reversed())
            edits.append((ranges[span.lowerBound].lowerBound..<ranges[span.upperBound - 1].upperBound,
                          swap.replacement + trailing))
        }
        var result = text
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.replaceSubrange(edit.range, with: edit.replacement)
        }
        return result
    }

    /// Vocabulary terms safe to boost. Measured on 241 dictations with
    /// `cbw 0 / minSimilarity 0.7`: every wrong swap came from a short term or a
    /// term whose tail is a common word ("able"/"table" → "Fable" ×10,
    /// "link" → "Ink" ×2), so both are skipped. `isDictionaryWord` is injected
    /// so tests don't depend on the host's spell checker.
    static func boostableTerms(_ terms: [String], isDictionaryWord: (String) -> Bool) -> [String] {
        terms.filter { term in
            let t = term.trimmingCharacters(in: .whitespaces)
            guard t.count > 4 else { return false }
            return !isDictionaryWord(String(t.dropFirst()).lowercased())
        }
    }

    // MARK: - Private

    private static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func tokenRanges(_ s: String) -> [Range<String.Index>] {
        s.split(whereSeparator: \.isWhitespace).map { $0.startIndex..<$0.endIndex }
    }

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "'" }

    private static func key(_ token: String) -> String {
        String(token.lowercased().filter(isWordChar))
    }

    /// For each index of `a`, the index of `b` it aligns to in a minimal diff, or nil.
    private static func alignedIndices(from a: [String], to b: [String]) -> [Int?] {
        let diff = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var result = [Int?](repeating: nil, count: a.count)
        var j = 0
        for i in a.indices where !removed.contains(i) {
            while inserted.contains(j) { j += 1 }
            result[i] = j
            j += 1
        }
        return result
    }
}
