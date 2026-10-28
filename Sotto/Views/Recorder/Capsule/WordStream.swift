import Foundation

// MARK: - WordStream
//
// Suffix-diff over the cumulative ASR partial (2026-07 revamp,
// design-mockups/01): the tape animates only APPENDED words; any rewrite of
// earlier content (ASR corrections, trims) rebuilds the visible tail
// instantly — never animate a correction. Pure value type so the diff is
// unit-testable (`WordStreamTests`).

struct StreamedWord: Identifiable, Equatable {
    /// Monotonic per-stream id — an appended word is a NEW identity (its
    /// entrance transition fires) while surviving prefix words keep theirs.
    let id: Int
    let text: String
}

struct WordStream: Equatable {
    enum Change { case none, appended, rewritten }

    /// The FULL token sequence of the current partial — diffing always runs
    /// against the whole prior partial so trims/rewrites that reach behind
    /// the visible window still resolve correctly; the window only decides
    /// which suffix is rendered.
    private var all: [StreamedWord] = []
    private var nextID = 0

    static let windowMax = 16

    /// Visible tail, capped at `windowMax` — older words sit under the leading
    /// fade mask anyway; the cap bounds layout work for long dictations.
    var words: [StreamedWord] { Array(all.suffix(Self.windowMax)) }

    init(partial: String = "") { ingest(partial) }

    @discardableResult
    mutating func ingest(_ partial: String) -> Change {
        let new = partial.split(whereSeparator: \.isWhitespace).map(String.init)
        let old = all.map(\.text)
        guard new != old else { return .none }
        let stable = zip(old, new).prefix(while: ==).count
        all.removeLast(old.count - stable)
        for text in new[stable...] {
            all.append(StreamedWord(id: nextID, text: text))
            nextID += 1
        }
        return (stable == old.count && new.count > old.count) ? .appended : .rewritten
    }
}
