import Foundation
import NaturalLanguage

/// Opt-in "Concise" pass over the final enhancement output. The cleanup model
/// removes fillers but keeps verbal crutches ("basically", "that particular",
/// a leading "So,"), because they are the speaker's words. This pass drops a
/// short, fixed list of them.
///
/// It only deletes: no word is added, replaced, or reordered, so it cannot
/// invent content the way a model rewrite can (a 4B rewrite dropped whole
/// sentences in 4 of 25 real dictations). Code-like lines are returned
/// byte-for-byte, the same rule `TranscriptPrepass` follows.
enum ConciseCleanup {
    static let userDefaultsKey = "ConciseEnhancement"

    static func apply(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let isCode = TranscriptPrepass.codeLikeLines(lines)
        return zip(lines, isCode).map { $1 ? $0 : conciseLine($0) }.joined(separator: "\n")
    }

    private static func conciseLine(_ line: String) -> String {
        // A list marker is not a sentence start; keep it and work on the body.
        let marker = listMarkerPrefix(line)
        var body = String(line.dropFirst(marker.count))
        body = replacing(#"\b(this|that|these|those) particular\b"#, with: "$1", in: body)
        body = deleting(#"\beach and (?=every\b)"#, in: body)
        body = deleting(#"\b(?:basically|essentially|literally|actually|honestly)\b,?\s*"#, in: body)
        body = deleting(#",\s*(?:you know|i mean)(?=,)"#, in: body)
        body = removingJustBeforeVerb(body)
        // "Okay, so basically, …" stacks openers; strip until none is left.
        var previous: String
        repeat {
            previous = body
            body = deleting(openerPattern, in: body, sentenceStartOnly: true)
        } while body != previous
        // Only a mark that ends a word: ".files" and "just .sh" keep their space.
        body = replacing(#" +([,.?!;:])(?=\s|$)"#, with: "$1", in: body)
        body = replacing(#",([.?!;:])(?=\s|$)"#, with: "$1", in: body)
        body = replacing(#" {2,}"#, with: " ", in: body)
        return marker + body
    }

    /// Discourse openers, only at a sentence start. A comma is required, except
    /// for "so", which is dropped bare unless it starts "so far", "so much"…
    /// "So that" stays: it can open a purpose clause, and "That" would not.
    private static let openerPattern =
        #"(?:(?:so|okay|ok|alright|all right|well|yeah|you know|i mean),\s*|so\s+(?!(?:far|much|many|long|too|on|that)\b))"#

    /// "just" is a crutch before a verb ("we can just delete it") and content
    /// before anything else ("we have just one route", "it is just a test").
    private static func removingJustBeforeVerb(_ text: String) -> String {
        guard text.range(of: "just", options: .caseInsensitive) != nil else { return text }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var words: [(range: Range<String.Index>, tag: NLTag?)] = []
        tagger.enumerateTags(in: text.startIndex ..< text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            words.append((range, tag))
            return true
        }
        var result = text
        for index in words.indices.reversed() where index + 1 < words.count {
            guard text[words[index].range].lowercased() == "just", words[index + 1].tag == .verb else { continue }
            result = deleting(offsets(words[index].range.lowerBound ..< words[index + 1].range.lowerBound, in: text), in: result)
        }
        return result
    }

    // MARK: - Helpers

    private static func listMarkerPrefix(_ line: String) -> String {
        guard TranscriptPrepass.isListItem(line) else { return "" }
        let indent = line.prefix { $0.isWhitespace }
        let rest = line.dropFirst(indent.count)
        let token = rest.prefix { !$0.isWhitespace }
        let space = rest.dropFirst(token.count).prefix { $0.isWhitespace }
        return String(indent + token + space)
    }

    private static func replacing(_ pattern: String, with template: String, in text: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: [.regularExpression, .caseInsensitive])
    }

    /// Deletes every match, last first, so the character offsets of the
    /// earlier matches still point at the same text.
    private static func deleting(_ pattern: String, in text: String, sentenceStartOnly: Bool = false) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            if sentenceStartOnly, !isSentenceStart(range.lowerBound, in: text) { continue }
            result = deleting(offsets(range, in: text), in: result)
        }
        return result
    }

    private static func offsets(_ range: Range<String.Index>, in text: String) -> Range<Int> {
        text.distance(from: text.startIndex, to: range.lowerBound) ..< text.distance(from: text.startIndex, to: range.upperBound)
    }

    /// Deletes the characters at `span` and, when they opened a sentence,
    /// capitalises the word that now opens it.
    private static func deleting(_ span: Range<Int>, in text: String) -> String {
        let lower = text.index(text.startIndex, offsetBy: span.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: span.upperBound)
        let opensSentence = isSentenceStart(lower, in: text)
        var result = text
        result.removeSubrange(lower ..< upper)
        let start = result.index(result.startIndex, offsetBy: span.lowerBound)
        guard opensSentence, start < result.endIndex, result[start].isLowercase else { return result }
        result.replaceSubrange(start ... start, with: String(result[start]).uppercased())
        return result
    }

    private static func isSentenceStart(_ index: String.Index, in text: String) -> Bool {
        let before = text[..<index].reversed().drop { $0 == " " }
        guard let mark = before.first else { return true }
        return mark == "." || mark == "?" || mark == "!"
    }
}
