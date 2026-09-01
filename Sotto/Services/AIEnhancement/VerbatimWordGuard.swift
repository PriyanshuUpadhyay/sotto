import Foundation

/// Puts back words the model softened.
///
/// The prompt already forbids this ("never upgrade the style or vocabulary",
/// "preserve … the speaker's tone"), and the on-device model overrides it
/// anyway: across one week of real dictation, 4 of the 15 word substitutions
/// the enhancement made were strong language replaced by a milder synonym
/// ("fucked" → "messed", "fuck ups" → "mistakes"). It is also inconsistent —
/// the same word survived untouched in other dictations that week.
///
/// The sanity check is the wrong lever for this: it answers a suspect output
/// with a hardened retry through the *same* model, which softens again. So the
/// restore is deterministic and runs after the model, not instead of it.
///
/// Scope is deliberately narrow. Only a word whose stem is in
/// `protectedStems` is ever restored, so a transcript containing no strong
/// language is returned byte-identical.
enum VerbatimWordGuard {

    /// Matched as a prefix of the lowercased word, so "fuck" also covers
    /// "fucked" / "fucking" / "fuckups". Ambiguous stems are deliberately
    /// absent — "ass" would capture "assessment", "hell" would capture
    /// "hello", and "dick" is a name.
    static let protectedStems: Set<String> = [
        "fuck", "shit", "damn", "crap", "piss", "bastard",
        "bitch", "bollock", "bugger", "arse", "twat", "wank",
    ]

    static func isProtected(_ word: String) -> Bool {
        let core = word.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard !core.isEmpty else { return false }
        return protectedStems.contains { core.hasPrefix($0) }
    }

    /// Returns `output` with every protected word from `raw` that the model
    /// replaced put back in its place.
    ///
    /// Alignment is a longest common subsequence over the lowercased word
    /// sequences. A run of raw words that LCS could not match is a span the
    /// model rewrote; when such a span contains a protected word, the raw span
    /// replaces whatever the model put there. A span with no protected word is
    /// left alone, so ordinary cleanup — filler removal, self-correction
    /// collapse, grammar fixes — passes through untouched.
    static func restore(raw: String, output: String) -> String {
        let rawWords = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard rawWords.contains(where: isProtected) else { return output }
        let outWords = output.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !outWords.isEmpty else { return output }

        var result: [String] = []
        var rawGap: [String] = []
        var outGap: [String] = []

        func flushGap() {
            // The raw span wins only when it carries a protected word;
            // otherwise the model's rewrite of that span stands.
            result.append(contentsOf: rawGap.contains(where: isProtected) ? rawGap : outGap)
            rawGap.removeAll()
            outGap.removeAll()
        }

        for step in align(rawWords.map(normalized), outWords.map(normalized)) {
            switch step {
            case .match(let rawIndex, let outIndex):
                flushGap()
                // The model's own token is kept on a match so its casing and
                // punctuation survive; only the rewritten spans are reverted.
                _ = rawIndex
                result.append(outWords[outIndex])
            case .rawOnly(let index):
                rawGap.append(rawWords[index])
            case .outputOnly(let index):
                outGap.append(outWords[index])
            }
        }
        flushGap()
        return result.joined(separator: " ")
    }

    private static func normalized(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private enum Step {
        case match(rawIndex: Int, outputIndex: Int)
        case rawOnly(Int)
        case outputOnly(Int)
    }

    /// Standard LCS table walk. Both inputs are one dictation, so the O(n·m)
    /// table is small.
    private static func align(_ a: [String], _ b: [String]) -> [Step] {
        var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        if !a.isEmpty && !b.isEmpty {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    lengths[i][j] = a[i] == b[j]
                        ? lengths[i + 1][j + 1] + 1
                        : max(lengths[i + 1][j], lengths[i][j + 1])
                }
            }
        }
        var steps: [Step] = []
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                steps.append(.match(rawIndex: i, outputIndex: j))
                i += 1; j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                steps.append(.rawOnly(i)); i += 1
            } else {
                steps.append(.outputOnly(j)); j += 1
            }
        }
        while i < a.count { steps.append(.rawOnly(i)); i += 1 }
        while j < b.count { steps.append(.outputOnly(j)); j += 1 }
        return steps
    }
}
