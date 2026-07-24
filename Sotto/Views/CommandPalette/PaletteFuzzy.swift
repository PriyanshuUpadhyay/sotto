import Foundation

/// Pure case-insensitive scoring for palette result ranking. Returns `nil`
/// when `query` is not even a subsequence of `text`. Higher score = better.
enum PaletteFuzzy {
    static func score(_ query: String, _ text: String) -> Int? {
        let q = query.lowercased()
        let t = text.lowercased()
        if q.isEmpty { return 0 }
        if t == q { return 1000 }
        if t.hasPrefix(q) { return 800 }
        if t.contains(q) {
            let wordBoundaryHit = t
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .contains { $0.hasPrefix(q) }
            return wordBoundaryHit ? 600 : 400
        }
        // Subsequence fallback.
        var idx = t.startIndex
        for qc in q {
            guard let found = t[idx...].firstIndex(of: qc) else { return nil }
            idx = t.index(after: found)
        }
        return 200
    }
}
