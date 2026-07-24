import Foundation
import Combine

/// Drives the palette card: holds the full command source, the live query, the
/// ranked `results`, and the keyboard `selectionIndex`. Ranking is synchronous
/// and pure (via `PaletteFuzzy`); the VIEW debounces typing before calling
/// `applyQuery` so we don't re-rank on every keystroke.
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
        selectionIndex = results.isEmpty ? 0 : min(selectionIndex, results.count - 1)
        if selectionIndex < 0 { selectionIndex = 0 }
        // Reset to top whenever the result set shrinks to keep selection visible.
        if selectionIndex >= results.count { selectionIndex = 0 }
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
