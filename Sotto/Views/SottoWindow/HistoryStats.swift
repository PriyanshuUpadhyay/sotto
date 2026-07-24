import Foundation

struct HistoryStats {
    let count: Int
    let avgWPM: Double
    let timeSavedSeconds: Double
    /// Fraction (0...1) of reviewed dictations pasted and never edited, or `nil`
    /// when no edit signals are retained. See `zeroEditRate(editRecords:)`.
    let zeroEditRate: Double?

    private static let averageTypingSpeed: Double = 35

    static func compute(from metrics: [SessionMetric],
                        editRecords: [EnhancementEditRecord] = []) -> HistoryStats {
        let count = metrics.count
        let totalWords = metrics.reduce(0) { $0 + $1.wordCount }
        let totalDuration = metrics.reduce(0.0) { $0 + $1.audioDuration }

        let avgWPM = totalDuration > 0 ? Double(totalWords) / (totalDuration / 60.0) : 0
        let estimatedTypingTime = (Double(totalWords) / averageTypingSpeed) * 60.0
        let timeSaved = max(estimatedTypingTime - totalDuration, 0)

        return HistoryStats(
            count: count,
            avgWPM: avgWPM,
            timeSavedSeconds: timeSaved,
            zeroEditRate: zeroEditRate(editRecords: editRecords)
        )
    }

    /// Today-scoped stats for the History stats band (words / avg WPM /
    /// dictation time / sessions since local midnight).
    struct Today: Equatable {
        let words: Int
        let avgWPM: Double
        let dictationSeconds: Double
        let sessions: Int
    }

    static func computeToday(from metrics: [SessionMetric],
                             now: Date = Date(),
                             calendar: Calendar = .current) -> Today {
        let startOfDay = calendar.startOfDay(for: now)
        let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? .distantFuture
        // Bounded both sides — future-dated metrics (clock skew, bad imports)
        // must not count as today.
        let today = metrics.filter { $0.timestamp >= startOfDay && $0.timestamp < startOfNextDay }
        let words = today.reduce(0) { $0 + $1.wordCount }
        let duration = today.reduce(0.0) { $0 + $1.audioDuration }
        return Today(
            words: words,
            avgWPM: duration > 0 ? Double(words) / (duration / 60.0) : 0,
            dictationSeconds: duration,
            sessions: today.count
        )
    }

    /// Fraction (0...1) of reviewed dictations that were pasted and never edited
    /// afterward — the product's "zero-edit rate" north-star.
    ///
    /// Both numerator and denominator come from the RETAINED edit-signal records
    /// only (grouped by dictation): a dictation is "edited" iff any of its
    /// signals changed the pasted text (`EditSignalSource.indicatesEdit`), and
    /// zero-edit otherwise (`.acceptedUnchanged` / `.thumbsDown`). Dictations
    /// whose signals were pruned (EditSignalService: 90 days / 200 records)
    /// drop out of BOTH sides — deriving the denominator from SessionMetric
    /// instead would silently count every pruned dictation as zero-edit,
    /// inflating the rate over time. Cap eviction is oldest-first and
    /// type-agnostic (EditSignalService.prune), so the retained sample stays
    /// unbiased between the edited and zero-edit classes. The UI labels the
    /// chip with the retention window. Returns `nil` when no signals are
    /// retained — nothing to rate.
    static func zeroEditRate(editRecords: [EnhancementEditRecord]) -> Double? {
        guard !editRecords.isEmpty else { return nil }
        var editedByDictation: [UUID: Bool] = [:]
        for record in editRecords {
            editedByDictation[record.transcriptionID] =
                (editedByDictation[record.transcriptionID] ?? false) || record.signalSource.indicatesEdit
        }
        let zeroEdit = editedByDictation.values.filter { !$0 }.count
        return Double(zeroEdit) / Double(editedByDictation.count)
    }
}
