import Foundation

extension TranscriptPrepass {

    // MARK: - emphasis

    /// Removes the Markdown bold the model sometimes puts around a word it
    /// finds notable — `a **shit** show` for `a shit show`.
    ///
    /// Only a syntactically valid Markdown pair, and only outside code: the
    /// opener must be followed by a non-space and the closer preceded by one,
    /// with no `**` between them. That is what separates the model's
    /// decoration from Python's `**kwargs, **options`, from an exponent
    /// (`x ** y ** z`), and from a pair that merely happens to be on the same
    /// line. `__…__` is not touched at all: `__init__` and Markdown bold have
    /// the same text, so no rule can tell them apart.
    static func emphasis(_ text: String) -> String {
        mapProseLines(text) { line in
            var stripped = line
            while let pair = boldPair(in: stripped) {
                stripped.removeSubrange(pair.close)
                stripped.removeSubrange(pair.open)
            }
            guard stripped != line else { return line }
            // Removing a marker can leave a double space behind; squeezing it
            // here is what keeps the whole chain idempotent.
            return stripped.split(separator: " ", omittingEmptySubsequences: true)
                .joined(separator: " ")
        }
    }

    /// Applies `transform` to every PROSE line and returns every code line
    /// byte-for-byte. The one place the code rule is enforced, so no pass can
    /// forget it.
    private static func mapProseLines(_ text: String, _ transform: (String) -> String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let isCode = codeLikeLines(lines)
        return zip(lines, isCode).map { $1 ? $0 : transform($0) }.joined(separator: "\n")
    }

    private static func boldPair(in line: String) -> (open: Range<String.Index>, close: Range<String.Index>)? {
        var search = line.startIndex
        while let open = line.range(of: "**", range: search ..< line.endIndex) {
            defer { search = open.upperBound }
            // A valid opener is followed by a non-space that is not another `*`.
            guard open.upperBound < line.endIndex else { return nil }
            let afterOpen = line[open.upperBound]
            guard !afterOpen.isWhitespace, afterOpen != "*" else { continue }
            var closeSearch = open.upperBound
            while let close = line.range(of: "**", range: closeSearch ..< line.endIndex) {
                closeSearch = close.upperBound
                let beforeClose = line[line.index(before: close.lowerBound)]
                guard !beforeClose.isWhitespace, beforeClose != "*" else { continue }
                // No third marker may sit inside the pair.
                guard line.range(of: "**", range: open.upperBound ..< close.lowerBound) == nil else { continue }
                return (open, close)
            }
        }
        return nil
    }

    /// A token split into the punctuation before it, the word, and the
    /// punctuation after it.
    private static func parts(_ token: String) -> (prefix: String, word: String, suffix: String) {
        let prefix = token.prefix { !$0.isLetter && !$0.isNumber }
        let rest = token.dropFirst(prefix.count)
        let suffix = rest.reversed().prefix { !$0.isLetter && !$0.isNumber }
        return (String(prefix), String(rest.dropLast(suffix.count)), String(suffix.reversed()))
    }

    // MARK: - contractions

    /// Restores the apostrophe in a contraction the model wrote without one —
    /// "whats" → "what’s", "dont" → "don’t". Speech-to-text drops it and a 3B
    /// model often copies the transcript's spelling straight through.
    ///
    /// The table holds ONLY spellings that are never an ordinary English word,
    /// so no local grammar is needed to be sure. "lets", "cant", "wont", "im",
    /// "id", "its", "well", "ill", "were", "wed" and "shed" are all excluded:
    /// each is a real word ("the API lets callers retry", "a cantilever beam")
    /// as often as a contraction. Code lines and all-uppercase tokens ("IM",
    /// "CANT") are left alone — an acronym is not a contraction.
    static func contractions(_ text: String) -> String {
        mapProseLines(text) { line in
            line.split(separator: " ", omittingEmptySubsequences: false).map { token -> String in
                let (prefix, word, suffix) = parts(String(token))
                guard !word.isEmpty, word != word.uppercased() || word.count == 1,
                      let fixed = contractionForms[word.lowercased()] else { return String(token) }
                let cased = word.first?.isUppercase == true && !fixed.hasPrefix("I")
                    ? fixed.prefix(1).uppercased() + fixed.dropFirst()
                    : fixed
                return prefix + cased + suffix
            }.joined(separator: " ")
        }
    }

    private static let contractionForms: [String: String] = [
        "dont": "don\u{2019}t", "doesnt": "doesn\u{2019}t", "didnt": "didn\u{2019}t",
        "isnt": "isn\u{2019}t", "arent": "aren\u{2019}t", "wasnt": "wasn\u{2019}t",
        "werent": "weren\u{2019}t", "havent": "haven\u{2019}t", "hasnt": "hasn\u{2019}t",
        "couldnt": "couldn\u{2019}t", "wouldnt": "wouldn\u{2019}t", "shouldnt": "shouldn\u{2019}t",
        "whats": "what\u{2019}s", "thats": "that\u{2019}s", "theyre": "they\u{2019}re",
        "youre": "you\u{2019}re", "ive": "I\u{2019}ve", "youve": "you\u{2019}ve",
        "weve": "we\u{2019}ve", "theyve": "they\u{2019}ve",
    ]

    // MARK: - lineBreaks

    /// Applies a spoken "new line" / "new paragraph" cue, but ONLY where the
    /// structure makes it unambiguous: the cue alone on its own line, which is
    /// how the model renders it when it recognised a cue and could not decide
    /// what to do with it.
    ///
    /// An inline cue is never applied. "replace new line with a space" and
    /// "the phrase new line is ambiguous" are ordinary instructions to a
    /// coding agent, and no denylist of preceding words can separate those
    /// from a real cue. A missed break costs one keystroke; a wrong one
    /// destroys a sentence.
    static func lineBreaks(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let isCode = codeLikeLines(lines)
        guard lines.count >= 3,
              zip(lines, isCode).contains(where: { !$1 && isOwnLineCue($0) != nil }) else { return text }

        var kept: [String] = []
        var separators: [String] = []
        var fromCue = Set<Int>()
        // The separator to use before the next kept line. A cue line sets it,
        // so the cue replaces the plain break the model put around it.
        var pending: String?
        for (line, code) in zip(lines, isCode) {
            if !code, let separator = isOwnLineCue(line), !kept.isEmpty {
                pending = separator
                continue
            }
            if !kept.isEmpty {
                separators.append(pending ?? "\n")
                if pending != nil { fromCue.insert(separators.count - 1) }
            }
            pending = nil
            kept.append(line)
        }
        guard !fromCue.isEmpty, kept.count == separators.count + 1 else { return text }

        var result = ""
        for (index, line) in kept.enumerated() {
            // The same sentence-aware termination `finish` uses: a question
            // keeps its question mark, a mark goes inside a closing quote, and
            // a list item or a code line is never punctuated.
            let piece = fromCue.contains(index) ? terminated(line) : line
            result += piece
            if index < separators.count { result += separators[index] }
        }
        return result
    }

    /// The separator a line asks for when the whole line is nothing but a cue.
    private static func isOwnLineCue(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!? "))
        switch t {
        case "new line", "newline": return "\n"
        case "new paragraph": return "\n\n"
        default: return nil
        }
    }
}
