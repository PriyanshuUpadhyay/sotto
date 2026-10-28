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

    static func isListMarker(_ token: String) -> Bool {
        if token == "-" || token == "*" || token == "\u{2022}" { return true }
        let digits = token.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return false }
        let rest = token.dropFirst(digits.count)
        return rest == "." || rest == ")"
    }

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
