import Foundation

enum WordDiffEngine {
    // Find word substitutions between original and edited text using LCS alignment
    static func findSingleWordSubstitutions(original: String, edited: String) -> [(original: String, replacement: String)] {
        let origTokens = tokenize(original)
        let editTokens = tokenize(edited)
        guard !origTokens.isEmpty, !editTokens.isEmpty else { return [] }

        let lcsIndices = lcsIndexPairs(origTokens, editTokens)

        var results = [(original: String, replacement: String)]()
        var oi = 0
        var ei = 0

        // Collect changed segments between each LCS anchor
        for (anchorO, anchorE) in lcsIndices {
            let origSegment = Array(origTokens[oi..<anchorO])
            let editSegment = Array(editTokens[ei..<anchorE])
            results.append(contentsOf: pairSegments(origSegment, editSegment))
            oi = anchorO + 1
            ei = anchorE + 1
        }

        // Trailing tokens after the last anchor
        let origTail = Array(origTokens[oi...])
        let editTail = Array(editTokens[ei...])
        results.append(contentsOf: pairSegments(origTail, editTail))

        return results
    }

    // Pair tokens from a changed segment into substitutions
    private static func pairSegments(_ orig: [String], _ edit: [String]) -> [(original: String, replacement: String)] {
        if orig.isEmpty || edit.isEmpty { return [] }

        // Equal length: pair 1:1, skip case-only matches
        if orig.count == edit.count {
            return zip(orig, edit).compactMap { a, b in
                a.lowercased() == b.lowercased() ? nil : (a, b)
            }
        }

        // Unequal length: merge/split — pair each original with each new replacement
        var results = [(original: String, replacement: String)]()
        for editWord in edit {
            let isCaseOnly = orig.contains(where: { $0.lowercased() == editWord.lowercased() })
            if !isCaseOnly {
                for origWord in orig {
                    results.append((origWord, editWord))
                }
            }
        }
        return results
    }

    // Compute LCS index pairs using case-insensitive comparison
    private static func lcsIndexPairs(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let m = a.count
        let n = b.count

        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if a[i - 1].lowercased() == b[j - 1].lowercased() {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find matched index pairs
        var pairs = [(Int, Int)]()
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1].lowercased() == b[j - 1].lowercased() {
                pairs.append((i - 1, j - 1))
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return pairs.reversed()
    }

    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }
}

extension WordDiffEngine {
    /// W12.A token-level diff op for inline diff rendering. Emitted in
    /// reading order — apply each op in sequence to reconstruct the edited
    /// text, with `.equal` and `.insert` segments visible and `.delete`
    /// segments shown stricken-through. See plan
    /// `docs/superpowers/plans/W12A-auto-cleanup-levels.md` §Task 5.
    enum DiffOp: Equatable {
        case equal(String)
        case insert(String)
        case delete(String)
    }

    static func tokenLevelDiff(original: String, edited: String) -> [DiffOp] {
        let origTokens = tokenize(original)
        let editTokens = tokenize(edited)
        guard !origTokens.isEmpty || !editTokens.isEmpty else { return [] }
        if origTokens.isEmpty { return editTokens.map { .insert($0) } }
        if editTokens.isEmpty { return origTokens.map { .delete($0) } }

        let lcsIndices = lcsIndexPairs(origTokens, editTokens)

        var ops = [DiffOp]()
        var oi = 0
        var ei = 0

        for (anchorO, anchorE) in lcsIndices {
            // Tokens in original before anchor that aren't in edited → delete
            while oi < anchorO {
                ops.append(.delete(origTokens[oi]))
                oi += 1
            }
            // Tokens in edited before anchor that aren't in original → insert
            while ei < anchorE {
                ops.append(.insert(editTokens[ei]))
                ei += 1
            }
            // The anchor itself is shared — emit as equal (use the edited
            // form's casing since post-cleanup capitalization wins).
            ops.append(.equal(editTokens[anchorE]))
            oi = anchorO + 1
            ei = anchorE + 1
        }

        // Trailing tail
        while oi < origTokens.count {
            ops.append(.delete(origTokens[oi]))
            oi += 1
        }
        while ei < editTokens.count {
            ops.append(.insert(editTokens[ei]))
            ei += 1
        }

        return ops
    }
}
