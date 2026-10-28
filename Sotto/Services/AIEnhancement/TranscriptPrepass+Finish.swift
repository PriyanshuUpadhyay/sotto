import Foundation

extension TranscriptPrepass {

    // MARK: - finish

    /// Capitalises the first word of every line and gives the last prose line
    /// a terminal mark — the two things a 3B model most often omits when it
    /// decides the transcript is already clean and echoes it back.
    ///
    /// Prose only. A code-like line (a URL, a path, a code span, a shell
    /// command, a single identifier) is returned byte-for-byte, so
    /// `npm install lodash`, `/tmp/build.log` and `main` survive. A list item
    /// is capitalised but never punctuated — the item owns no sentence mark.
    /// The mark is `?` only where the syntax is interrogative (`isQuestion`),
    /// `.` otherwise, and it is inserted BEFORE a closing quote or bracket.
    static func finish(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = trimmed.components(separatedBy: .newlines)
        let isCode = codeLikeLines(lines)
        for index in lines.indices where !isCode[index] {
            lines[index] = capitalizeFirstWord(lines[index])
        }
        guard let last = lines.indices.last, !lines[last].isEmpty, !isCode[last] else {
            return lines.joined(separator: "\n")
        }
        lines[last] = terminated(lines[last])
        return lines.joined(separator: "\n")
    }

    /// Gives one line its sentence mark, or returns it untouched. Prose only:
    /// a code-like line and a list item both own no sentence mark, and the
    /// mark goes INSIDE a closing quote or bracket.
    static func terminated(_ line: String) -> String {
        guard !isCodeLike(line), !isListItem(line) else { return line }
        let closing = String(line.reversed().prefix { closingMarkSet.contains($0) }.reversed())
        let body = String(line.dropLast(closing.count))
        guard let last = body.last, !sentenceMarks.contains(last) else { return line }
        return body + (isQuestion(body) ? "?" : ".") + closing
    }

    /// Upper-cases a line's first word, skipping an opening quote or bracket
    /// and a list marker, and only when the word is entirely lowercase letters
    /// — an internal apostrophe included, so `what’s the status` gains its
    /// capital after `contractions` has run. `getUserProfile`, `iPhone` and
    /// `v2` keep their shape.
    private static func capitalizeFirstWord(_ line: String) -> String {
        var t = line
        var words = t.split(whereSeparator: \.isWhitespace).map(String.init)
        if let first = words.first, isListMarker(first) { words.removeFirst() }
        guard let word = words.first else { return t }
        let core = String(word.drop { openingMarks.contains($0) })
        guard let head = core.first, head.isLetter,
              core.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "\u{2019}" }),
              core == core.lowercased(), let at = t.range(of: core)?.lowerBound else { return t }
        t.replaceSubrange(at ... at, with: String(t[at]).uppercased())
        return t
    }

    /// Whether the text is a question by SYNTAX, not by its first word alone.
    /// English fronts either an interrogative followed by an auxiliary
    /// ("what is", "how do", "how many", "what if") or an auxiliary followed
    /// by its subject ("can you", "did it"). A subordinate clause ("what I
    /// mean is…", "how this works is simple") and the imperative "do it"
    /// match neither, and get a period. A subject question ("what happened",
    /// "who called") is indistinguishable from a statement fragment by
    /// syntax alone, so it keeps the period too.
    static func isQuestion(_ text: String) -> Bool {
        let words = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "\u{2019}" })
            .map { String($0).replacingOccurrences(of: "\u{2019}", with: "'") }
        guard let first = words.first else { return false }
        // "what's the status" — the contraction carries its own auxiliary.
        if contractedInterrogatives.contains(first) { return true }
        guard words.count >= 2 else { return false }
        let second = words[1]
        if interrogatives.contains(first) {
            if first == "what", second == "if" { return true }
            return auxiliaries.contains(second) || interrogativeQualifiers.contains(second)
        }
        // The imperative "do it now" is not a question; "did it work" is.
        if first == "do", second == "it" { return false }
        guard auxiliaries.contains(first) else { return false }
        if questionSubjects.contains(second) { return true }
        // "Did the build finish?" — a determiner is a subject too, but only
        // after an auxiliary that has no imperative reading. "Do the migration
        // first" and "Have a look" are commands, not questions.
        return !imperativeAuxiliaries.contains(first) && determiners.contains(second)
    }

    private static let interrogatives: Set<String> =
        ["what", "who", "whom", "whose", "where", "when", "why", "how", "which"]
    private static let contractedInterrogatives: Set<String> =
        ["what's", "who's", "where's", "when's", "why's", "how's"]
    private static let interrogativeQualifiers: Set<String> =
        ["many", "much", "long", "far", "often", "soon", "big", "about", "come"]
    private static let auxiliaries: Set<String> = [
        "is", "are", "was", "were", "do", "does", "did", "can", "could",
        "should", "would", "will", "have", "has", "had", "am", "may", "might", "shall",
    ]
    private static let imperativeAuxiliaries: Set<String> = ["do", "have"]
    private static let determiners: Set<String> = [
        "the", "a", "an", "my", "your", "our", "his", "her", "their", "its",
        "any", "all", "every", "both", "either",
    ]
    private static let questionSubjects: Set<String> = [
        "you", "we", "i", "it", "he", "she", "they", "this", "that", "there",
        "these", "those", "anyone", "anybody", "someone", "somebody",
    ]

    private static let openingMarks: Set<Character> = ["\"", "'", "(", "[", "\u{201C}", "\u{2018}"]

    /// A real sentence mark. A closing quote or bracket is NOT one — `"ship
    /// it"` still needs its period, inserted inside the quote.
    private static let sentenceMarks: Set<Character> = [".", "!", "?", ":", ";", "\u{2026}"]

    private static let closingMarkSet: Set<Character> =
        ["\"", "'", ")", "]", "}", "\u{00BB}", "\u{203A}", "\u{2019}", "\u{201D}"]
}
