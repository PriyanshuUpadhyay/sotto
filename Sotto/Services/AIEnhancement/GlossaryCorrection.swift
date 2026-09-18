import Foundation

/// Grammar-constrained glossary repair.
///
/// The enhancement pass deliberately never rewrites words — its prompt forbids
/// it, because a 0.6B model asked to "fix the transcript" invents content. That
/// leaves every proper-noun mishear ("clouds" for Claude, "page nation" for
/// pagination) unrepaired.
///
/// This pass asks the same model a much narrower question and makes the narrow
/// answer the ONLY thing it is able to emit. A GBNF grammar constrains output to
/// a list of `find`/`replace` pairs where `replace` is a literal alternation of
/// the user's own glossary terms, so the model cannot name a replacement that is
/// not already in the glossary. `apply` then does plain, auditable string
/// substitution and drops any pair whose `find` is not actually present.
///
/// Rewriting is therefore structurally impossible rather than
/// prompt-discouraged: the worst case is a wrong-but-in-glossary substitution of
/// a span that really occurs, not a reworded transcript.
enum GlossaryCorrection {

    /// One proposed repair. `find` is a span of the transcript; `replace` is a
    /// glossary term.
    struct Patch: Equatable {
        let find: String
        let replace: String
    }

    /// Longest glossary term, in words, that the grammar will let `find` span.
    /// Covers the merge-shatter case ("page nation" → pagination) without
    /// letting the model claim a whole clause.
    static let maxFindWords = 3

    // MARK: - Grammar

    /// GBNF for a JSON array of patches. `replace` is a closed alternation over
    /// `glossary`, which is what makes an invented replacement unrepresentable.
    /// `find` is free text, but bounded and checked against the transcript in
    /// `apply`, because enumerating every legal span in the grammar would make
    /// it enormous for a long dictation.
    ///
    /// Returns nil for an empty glossary — there is nothing to correct toward,
    /// and a grammar with an empty alternation does not parse.
    static func grammar(glossary: [String]) -> String? {
        let terms = glossary
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }

        let alternatives = terms.map { "\"\\\"\($0.gbnfEscaped)\\\"\"" }.joined(separator: " | ")
        return """
        root ::= "[]" | "[" patch ("," patch)* "]"
        patch ::= "{\\"find\\":" find ",\\"replace\\":" replace "}"
        replace ::= \(alternatives)
        find ::= "\\"" findchar+ "\\""
        findchar ::= [^"\\\\\\n]
        """
    }

    // MARK: - Parse

    /// Decodes the model's grammar-constrained output. Returns an empty list for
    /// anything unparseable — the pass is best-effort and must never break a
    /// dictation.
    static func parse(_ raw: String) -> [Patch] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }
        return items.compactMap { item in
            guard let find = item["find"], let replace = item["replace"],
                  !find.isEmpty, !replace.isEmpty
            else { return nil }
            return Patch(find: find, replace: replace)
        }
    }

    // MARK: - Apply

    /// Applies the patches the transcript actually supports.
    ///
    /// Every patch must clear three gates, all of which exist because the model
    /// chooses `find` freely:
    /// 1. `replace` is a real glossary term (case-insensitive) — the grammar
    ///    already forces this, but a caller may pass unconstrained output.
    /// 2. `find` occurs in the transcript, case-insensitively.
    /// 3. `find` is at most `maxFindWords` words, so a patch cannot swallow a
    ///    clause.
    ///
    /// A patch that would replace a span with itself is dropped. Substitution is
    /// case-insensitive and applies to every occurrence, matching
    /// `WordReplacementService`.
    static func apply(_ patches: [Patch], to transcript: String, glossary: [String]) -> String {
        let allowed = Set(glossary.map { $0.lowercased() })
        var output = transcript
        for patch in patches {
            guard allowed.contains(patch.replace.lowercased()) else { continue }
            guard patch.find.split(separator: " ").count <= maxFindWords else { continue }
            guard patch.find.caseInsensitiveCompare(patch.replace) != .orderedSame else { continue }
            guard output.range(of: patch.find, options: .caseInsensitive) != nil else { continue }
            output = output.replacingOccurrences(
                of: patch.find, with: patch.replace, options: [.caseInsensitive])
        }
        return output
    }

    /// Instruction for the correction call. Short on purpose: the grammar, not
    /// the wording, is what holds the model to the format.
    static func prompt(transcript: String, glossary: [String]) -> String {
        """
        Find words in the transcript that are mishearings of these terms: \
        \(glossary.joined(separator: ", ")).

        Reply with a JSON array of {"find","replace"} objects. "find" is the \
        misheard text exactly as it appears in the transcript. "replace" is the \
        correct term. Reply with [] if nothing is misheard. Do not fix grammar, \
        punctuation, or anything else.

        Transcript: \(transcript)
        """
    }
}

private extension String {
    /// Escapes a term for a GBNF double-quoted literal that is itself inside a
    /// JSON string literal. Backslash first, or it would re-escape the quotes
    /// this adds.
    var gbnfEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\\\\\")
            .replacingOccurrences(of: "\"", with: "\\\\\"")
    }
}
