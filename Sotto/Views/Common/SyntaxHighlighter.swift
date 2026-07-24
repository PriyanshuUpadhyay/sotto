import SwiftUI
import AppKit

/// Lightweight, language-agnostic syntax tinting for code transcripts (P12).
///
/// This is deliberately NOT a real lexer — it's a cheap, ordered regex pass that
/// colors the four deferred syntax hues kept in `Palette` so a dictated code
/// snippet reads *as code* in the History inspector instead of as flat prose:
///
///   keyword       → `Palette.synEnhance`     (keyword-violet  #c46bf0)
///   function call → `Palette.stateProcessing`(function-blue   #7fb4ff)
///   string        → `Palette.stateCommit`    (string-green    #8af06e)
///   number        → `Palette.stateFail`      (number-amber    #ffb86b)
///   comment       → `Palette.inkTertiary`    (dimmed)
///   everything else → `Palette.inkPrimary`
///
/// Detection (`isLikelyCode`) is a simple scored heuristic — no Power-Mode flag
/// exists on `Transcription`, so we infer from the text itself and bias toward
/// false-negatives (prose must never get rainbow-tinted). Both functions are
/// pure over their `String` input so they're unit-testable without rendering.
enum SyntaxHighlighter {
    /// Multi-language keyword set (Swift / Python / JS / C-ish). Small on
    /// purpose — enough to signal "code", not an exhaustive grammar.
    static let keywords: Set<String> = [
        "func", "let", "var", "return", "if", "else", "for", "while", "switch",
        "case", "guard", "do", "try", "catch", "throw", "throws", "async", "await",
        "import", "from", "as", "in", "is", "self", "init", "deinit", "struct",
        "class", "enum", "protocol", "extension", "static", "public", "private",
        "internal", "fileprivate", "open", "def", "lambda", "elif", "with", "pass",
        "const", "function", "void", "new", "extends", "implements", "interface",
        "type", "true", "false", "nil", "null", "none", "and", "or", "not", "then",
        "end", "begin", "where", "yield", "break", "continue", "default", "match",
    ]

    /// Code-signal substrings + their weights for `isLikelyCode`.
    private static let signalTokens: [String] = [
        "func ", "def ", "class ", "struct ", "enum ", "import ", "const ",
        "let ", "var ", "function ", "public ", "private ", "return ", "=> ",
        "#include", "</", "){", "});", " == ", " != ", " => ", "::",
    ]

    /// Heuristic: does this transcript look like a code snippet? Scored signals;
    /// requires ≥2 to flip true so ordinary prose ("let me know if…", "var" in a
    /// sentence) stays plain. Very short strings never qualify.
    static func isLikelyCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return false }

        var score = 0
        for token in signalTokens where text.contains(token) { score += 1 }

        // Punctuation density typical of code (braces / parens / semicolons).
        let codePunct = text.reduce(into: 0) { acc, ch in
            if "{}();".contains(ch) { acc += 1 }
        }
        if codePunct >= 3 { score += 1 }

        // A line that ends in `{`, `}`, `;`, or `:` is a strong structural cue.
        let lines = text.split(whereSeparator: \.isNewline)
        let structuralLines = lines.filter { line in
            guard let last = line.trimmingCharacters(in: .whitespaces).last else { return false }
            return "{};:".contains(last)
        }
        if structuralLines.count >= 1 { score += 1 }

        return score >= 2
    }

    /// Build a syntax-tinted `AttributedString`. Passes run in priority order;
    /// once a character range is claimed by a higher-priority token (comment /
    /// string) lower passes skip it, so a keyword inside a string stays green.
    static func highlight(_ source: String) -> AttributedString {
        let mutable = NSMutableAttributedString(string: source)
        let nsString = source as NSString
        let full = NSRange(location: 0, length: nsString.length)
        mutable.addAttribute(.foregroundColor, value: NSColor(Palette.inkPrimary), range: full)

        var claimed = IndexSet()

        func colorize(_ pattern: String, _ color: Color, captureGroup: Int = 0) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            let nsColor = NSColor(color)
            regex.enumerateMatches(in: source, options: [], range: full) { match, _, _ in
                guard let match, match.numberOfRanges > captureGroup else { return }
                let range = match.range(at: captureGroup)
                guard range.location != NSNotFound, range.length > 0 else { return }
                let intRange = range.location ..< (range.location + range.length)
                guard claimed.intersection(IndexSet(integersIn: intRange)).isEmpty else { return }
                mutable.addAttribute(.foregroundColor, value: nsColor, range: range)
                claimed.insert(integersIn: intRange)
            }
        }

        // 1. Comments (line + block) — win over everything inside them.
        colorize(#"(//[^\n]*|#[^\n]*|/\*[\s\S]*?\*/)"#, Palette.inkTertiary)
        // 2. String / char literals.
        colorize(#"("(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')"#, Palette.stateCommit)
        // 3. Keywords (whole-word).
        let keywordAlternation = keywords.sorted().joined(separator: "|")
        colorize(#"\b(?:\#(keywordAlternation))\b"#, Palette.synEnhance)
        // 4. Function-call identifiers — name immediately followed by `(`.
        colorize(#"\b([A-Za-z_][A-Za-z0-9_]*)\s*\("#, Palette.stateProcessing, captureGroup: 1)
        // 5. Numeric literals (int / float / hex).
        colorize(#"\b(?:0x[0-9A-Fa-f]+|\d+\.?\d*)\b"#, Palette.stateFail)

        return AttributedString(mutable)
    }
}
