import Foundation
import Combine

/// Drives the palette card: holds the full command source, the live query, the
/// ranked `results`, and the keyboard `selectionIndex`. Ranking is synchronous
/// and pure (via `PaletteFuzzy`), so the view calls `applyQuery` on every
/// keystroke — no debounce sits on the palette's input path.
@MainActor
final class CommandPaletteModel: ObservableObject {
    @Published private(set) var results: [PaletteCommand] = []
    @Published var selectionIndex: Int = 0

    private var source: [PaletteCommand] = []

    func setSource(_ commands: [PaletteCommand]) {
        source = commands
    }

    func applyQuery(_ query: String) {
        results = Self.rank(source, query: query)
        // A new query is a new ranking: the best match is row 0, so ⏎ can never
        // run a row that belonged to the previous result set.
        selectionIndex = 0
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectionIndex = max(0, min(results.count - 1, selectionIndex + delta))
    }

    var selectedCommand: PaletteCommand? {
        guard results.indices.contains(selectionIndex) else { return nil }
        return results[selectionIndex]
    }

    /// Pure ranking. Empty query preserves the source (provider) order.
    static func rank(_ commands: [PaletteCommand], query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return commands }
        return commands
            .compactMap { cmd -> (PaletteCommand, Int)? in
                let titleScore = PaletteFuzzy.score(q, cmd.title).map { $0 * 2 }
                let subScore = PaletteFuzzy.score(q, cmd.subtitle)
                guard let best = [titleScore, subScore].compactMap({ $0 }).max() else { return nil }
                return (cmd, best)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }
}
