import Foundation

/// Deterministic cleanup of the model's OUTPUT — a safety net for the stutters
/// and fillers the model leaves behind, never a pre-pass. The model must see
/// the raw transcript: pre-cleaning it made the input look finished, and AFM
/// then echoed it back with no capital and no terminal punctuation.
/// `EnhancementSanityCheck.deterministicCleanup` also builds on this.
///
/// It only removes noise that is certain: standalone fillers, an immediately
/// repeated word or 2-4 word phrase, and stray whitespace. "like" and "you
/// know" stay — they are as often real content as filler, so the model owns
/// them. A run made only of numbers (digits or spoken number words) or single
/// letters is never de-duplicated: a spoken code or phone number ("4 4 7 2",
/// "two two five five") repeats on purpose.
///
/// Line structure survives, so applying this to a model output cannot flatten
/// a numbered list or a paragraph break. `clean` is idempotent: cleaning an
/// already-cleaned string returns it unchanged.
///
/// The five passes below run on the model's output after `clean`. Every one of
/// them obeys the same rule: **a wrong change is worse than a missed one.**
/// This app's transcripts are instructions to coding agents, so a line that
/// might be code, a path, a command, or an identifier is left exactly as it
/// is, and any construction whose reading is ambiguous stays as words.
enum TranscriptPrepass {

    // MARK: - Line classification (shared by every pass)

    /// Whether each line is code that no pass may touch. Fence state is
    /// tracked across lines, so every line inside a ``` or ~~~ block counts,
    /// not only the fence markers themselves.
    ///
    /// The open fence remembers its character AND its length, because only a
    /// matching delimiter closes it: a `~~~` line inside a ``` block is body
    /// text, not a close. A fence is recognised after indentation and after a
    /// list marker, so an indented or bulleted block still protects its body.
    /// An unterminated fence protects every line to the end, which is the safe
    /// direction.
    static func codeLikeLines(_ lines: [String]) -> [Bool] {
        var open: (marker: Character, length: Int)?
        return lines.map { line in
            guard let fence = fenceDelimiter(line) else {
                return open != nil || isCodeLike(line)
            }
            if let current = open {
                // Only the same character, at least as long, can close it.
                if fence.marker == current.marker, fence.length >= current.length { open = nil }
            } else {
                open = fence
            }
            return true
        }
    }

    /// The fence a line opens or closes, after optional indentation and an
    /// optional list marker — `- ```swift` opens a fence just as ```` ```swift ````
    /// does.
    private static func fenceDelimiter(_ line: String) -> (marker: Character, length: Int)? {
        var t = Substring(line.trimmingCharacters(in: .whitespaces))
        if let first = t.split(whereSeparator: \.isWhitespace).first, isListMarker(String(first)) {
            t = t.dropFirst(first.count).drop(while: \.isWhitespace)
        }
        guard let marker = t.first, marker == "`" || marker == "~" else { return nil }
        let length = t.prefix { $0 == marker }.count
        guard length >= 3 else { return nil }
        return (marker, length)
    }

    /// A line that must never be capitalised, punctuated, or reflowed: it is
    /// code, a path, a URL, a command, or a bare identifier, and any change to
    /// it is data corruption rather than cleanup.
    static func isCodeLike(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        if t.hasPrefix("```") || t.hasPrefix("~~~") { return true }
        if t.contains("`") { return true }
        if t.contains("://") { return true }
        if t.hasPrefix("/") || t.hasPrefix("~/") || t.hasPrefix("./") || t.hasPrefix("../") { return true }
        let words = t.split(whereSeparator: \.isWhitespace).map(String.init)
        // A single token is an identifier, a branch, a file name — never prose.
        if words.count == 1 { return true }
        guard let first = words.first?.lowercased() else { return false }
        if unambiguousCommands.contains(first) { return true }
        // A tool whose name is also an ordinary English word defaults to CODE.
        // A make target, a file name and a subcommand are all open sets, so no
        // list can prove an unknown argument is prose — but a short list of
        // two-word openings can prove the prose reading. Everything else keeps
        // its command shape.
        guard ambiguousCommands.contains(first) else { return false }
        guard words.count >= 2 else { return true }
        return !proseOpenings.contains("\(first) \(words[1].lowercased())")
    }

    /// The two-word openings that prove an ambiguous tool name is prose. Short
    /// on purpose: anything not listed keeps the command reading, because
    /// corrupting a command is worse than missing a capital.
    private static let proseOpenings: Set<String> = [
        "go to", "go back", "go ahead", "go through", "go over", "go with",
        "make the", "make sure", "make it", "make a", "make this", "make that",
        "cat is", "cat was", "touch the", "touch it", "touch this",
        "echo that", "echo it", "echo the", "echo is",
        "swift is", "swift was", "cd into",
    ]

    /// Tool names that are never an ordinary English word, so the first token
    /// alone settles it.
    private static let unambiguousCommands: Set<String> = [
        "npm", "npx", "yarn", "pnpm", "git", "brew", "ls", "rm", "mv", "cp",
        "xcodebuild", "python", "python3", "pip", "uv", "node", "cargo",
        "docker", "kubectl", "curl", "ssh", "sudo", "chmod", "grep", "rg", "sed",
    ]

    /// Tool names that are also ordinary English words. Each still defaults to
    /// the command reading; only `proseOpenings` overrides it.
    private static let ambiguousCommands: Set<String> =
        ["go", "make", "cat", "touch", "echo", "cd", "swift"]

    /// `1.`, `2)`, `-`, `*`, `•` — the marker that opens a list item.
    static func isListItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let first = t.split(whereSeparator: \.isWhitespace).first else { return false }
        return isListMarker(String(first))
    }

    private static func isListMarker(_ token: String) -> Bool {
        if token == "-" || token == "*" || token == "\u{2022}" { return true }
        let digits = token.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return false }
        let rest = token.dropFirst(digits.count)
        return rest == "." || rest == ")"
    }

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
    private static func terminated(_ line: String) -> String {
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

    static let fillers: Set<String> = ["um", "uh", "uhm", "er", "erm", "hmm", "mm", "mhm"]

    /// The longest repeated run this collapses. Also the bound on how far the
    /// scan has to back up after a removal — see `collapseRepeats`.
    private static let maxRunLength = 4

    static func clean(_ text: String) -> String {
        // CRLF first: splitting on the newline set would otherwise turn "\r\n"
        // into a spurious blank line between the two real ones.
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map(cleanLine)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `isWhitespace` rather than a literal space/tab, so a non-breaking space
    /// or any other Unicode separator still divides tokens.
    private static func cleanLine(_ line: String) -> String {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        let withoutFillers = tokens.filter { !fillers.contains(bare($0)) }
        return collapseRepeats(withoutFillers).joined(separator: " ")
    }

    private static let edgePunctuation = CharacterSet(
        charactersIn: ",.!?;:\"'()[]{}-–—…\u{2018}\u{2019}\u{201C}\u{201D}")

    /// The comparison key for a token: lowercased, without the punctuation that
    /// rides on its edges, so "the," and "the" count as the same word.
    private static func bare(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: edgePunctuation)
    }

    /// The run of edge punctuation a token ends with — `"!”"` for `wait!”`,
    /// empty for `wait`.
    private static func trailingPunctuation(_ token: String) -> String {
        let count = token.reversed().prefix {
            $0.unicodeScalars.allSatisfy(edgePunctuation.contains)
        }.count
        return String(token.suffix(count))
    }

    /// Closing marks that can sit AFTER the sentence mark they enclose.
    private static let closingMarks = CharacterSet(
        charactersIn: "\"')]}\u{00BB}\u{203A}\u{2019}\u{201D}")

    private static let clauseMarks: Set<Character> = [",", ".", "!", "?", ";", ":", "\u{2026}"]

    /// Whether a token closes a clause or sentence, so what follows it is a
    /// fresh thought rather than a stutter of it. The mark can sit inside a
    /// closing quote or bracket — `He shouted “Wait!” Wait for me.` ends its
    /// first clause at the `!`, not at the `”` after it.
    private static func endsClause(_ token: String) -> Bool {
        let afterClosing = token.reversed().drop {
            $0.unicodeScalars.allSatisfy(closingMarks.contains)
        }
        guard let last = afterClosing.first else { return false }
        return clauseMarks.contains(last)
    }

    private static let numberWords: Set<String> = [
        "zero", "oh", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
        "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
        "eighty", "ninety", "hundred", "thousand", "million",
    ]

    /// A token that must never be treated as a stutter. A numeral, a spoken
    /// number word, or a letter on its own is how a code or a phone number is
    /// dictated: "two two five five" and "4 4 7 2" repeat on purpose.
    private static func isSpokenCode(_ bare: String) -> Bool {
        bare.count == 1 || bare.allSatisfy(\.isNumber) || numberWords.contains(bare)
    }

    /// Drops the second copy of an immediately repeated run of 1-4 words,
    /// longest run first so "for the for the" collapses as a phrase rather
    /// than leaving "the the" behind.
    private static func collapseRepeats(_ tokens: [String]) -> [String] {
        var words = tokens
        var bares = tokens.map(bare)
        var i = 0
        while i < words.count {
            var collapsed = false
            for n in stride(from: maxRunLength, through: 1, by: -1) {
                guard i + 2 * n <= words.count else { continue }
                let first = Array(bares[i ..< (i + n)])
                guard first == Array(bares[(i + n) ..< (i + 2 * n)]) else { continue }
                guard !first.contains(where: \.isEmpty) else { continue }
                guard !first.allSatisfy(isSpokenCode) else { continue }
                // A repeat across a clause boundary is not a stutter:
                // "ship it, it is ready" says "it" twice on purpose.
                guard !endsClause(words[i + n - 1]) else { continue }

                // The removed copy can own punctuation the kept one does not —
                // “Wait wait!” keeps only “Wait without this. Move that trailing
                // run over, unless the kept token already ends in punctuation of
                // its own (“Wait” “wait” must not become “Wait””).
                let lastKept = i + n - 1
                if trailingPunctuation(words[lastKept]).isEmpty {
                    words[lastKept] += trailingPunctuation(words[i + 2 * n - 1])
                }
                words.removeSubrange((i + n) ..< (i + 2 * n))
                bares.removeSubrange((i + n) ..< (i + 2 * n))
                collapsed = true
                break
            }
            if collapsed {
                // Closing the gap can create a repeat that starts BEFORE i, and
                // the scan has already passed those positions. A new match at
                // start s needs its second copy to reach the join, so
                // s + 2m > i + n with m <= maxRunLength and n >= 1 — that is,
                // s > i - 2 * maxRunLength. Backing up that far is enough, and
                // keeps the pass linear where a restart from zero would not.
                i = max(0, i - 2 * maxRunLength)
            } else {
                i += 1
            }
        }
        return words
    }
}
