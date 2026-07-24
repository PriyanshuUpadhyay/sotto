import XCTest
import SwiftUI
@testable import Sotto

@MainActor
final class HistoryStatsTests: XCTestCase {

    private func makeMetric(wordCount: Int, audioDuration: TimeInterval,
                            enhanced: Bool = false, tid: UUID = UUID()) -> SessionMetric {
        SessionMetric(
            transcriptionId: tid,
            wordCount: wordCount,
            audioDuration: audioDuration,
            transcriptionModelName: nil,
            transcriptionDuration: nil,
            speedFactor: nil,
            powerModeName: nil,
            aiEnhancementModelName: enhanced ? "gpt" : nil,
            enhancementDuration: nil
        )
    }

    private func editRecord(tid: UUID, source: EditSignalSource) -> EnhancementEditRecord {
        EnhancementEditRecord(rawText: "r", enhancedText: "e", finalText: "f",
                              appBundleID: nil, transcriptionID: tid, enhancedHash: "h",
                              editKind: .style, signalSource: source)
    }

    func test_compute_emptyArray_isZeroNoDivideByZero() {
        let stats = HistoryStats.compute(from: [])
        XCTAssertEqual(stats.count, 0)
        XCTAssertEqual(stats.avgWPM, 0)
        XCTAssertEqual(stats.timeSavedSeconds, 0)
        XCTAssertNil(stats.zeroEditRate)
    }

    // MARK: - zeroEditRate (denominator = retained edit signals, per dictation)

    func test_zeroEditRate_noSignals_isNil() {
        XCTAssertNil(HistoryStats.zeroEditRate(editRecords: []))
    }

    func test_zeroEditRate_oneOfFourEdited_is075() {
        let records = [
            editRecord(tid: UUID(), source: .edit),
            editRecord(tid: UUID(), source: .acceptedUnchanged),
            editRecord(tid: UUID(), source: .acceptedUnchanged),
            editRecord(tid: UUID(), source: .thumbsDown),
        ]
        XCTAssertEqual(HistoryStats.zeroEditRate(editRecords: records)!, 0.75, accuracy: 0.0001)
    }

    func test_zeroEditRate_acceptedUnchangedAndThumbsDown_countAsZeroEdit() {
        let records = [editRecord(tid: UUID(), source: .acceptedUnchanged),
                       editRecord(tid: UUID(), source: .thumbsDown)]
        XCTAssertEqual(HistoryStats.zeroEditRate(editRecords: records)!, 1.0, accuracy: 0.0001)
    }

    func test_zeroEditRate_revertRaw_countsAsEdit() {
        XCTAssertEqual(HistoryStats.zeroEditRate(editRecords: [editRecord(tid: UUID(), source: .revertRaw)])!,
                       0.0, accuracy: 0.0001)
    }

    func test_zeroEditRate_multipleSignalsForOneDictation_countOnce() {
        let a = UUID()
        // Same dictation: an accept then an edit — one denominator entry, edited.
        let records = [editRecord(tid: a, source: .acceptedUnchanged),
                       editRecord(tid: a, source: .edit),
                       editRecord(tid: UUID(), source: .acceptedUnchanged)]
        XCTAssertEqual(HistoryStats.zeroEditRate(editRecords: records)!, 0.5, accuracy: 0.0001)
    }

    func test_zeroEditRate_prunedSignals_dictationDropsOutInsteadOfCountingZeroEdit() {
        // 5 enhanced dictations exist as metrics, but only ONE still has a
        // retained signal (the rest pruned). The pruned four must NOT count as
        // zero-edit — the rate is over signals only, so it's 0.0, not 0.8.
        let a = UUID()
        let metrics = (0..<5).map { i in
            makeMetric(wordCount: 10, audioDuration: 5, enhanced: true, tid: i == 0 ? a : UUID())
        }
        let stats = HistoryStats.compute(from: metrics, editRecords: [editRecord(tid: a, source: .edit)])
        XCTAssertEqual(stats.zeroEditRate!, 0.0, accuracy: 0.0001)
    }

    func test_compute_knownFixture_countWPMAndTimeSaved() {
        let metrics = [
            makeMetric(wordCount: 150, audioDuration: 60),
            makeMetric(wordCount: 200, audioDuration: 60),
        ]
        let stats = HistoryStats.compute(from: metrics)
        XCTAssertEqual(stats.count, 2)
        // 350 words over 120s => 350 / (120/60) = 175 wpm (matches MetricsContent).
        XCTAssertEqual(stats.avgWPM, 175, accuracy: 0.0001)
        // typing time at 35 wpm = (350/35)*60 = 600s; saved = 600 - 120 = 480s.
        XCTAssertEqual(stats.timeSavedSeconds, 480, accuracy: 0.0001)
    }

    // MARK: - computeToday — the History stats band's today-scoped numbers

    func test_computeToday_filtersToStartOfDay_andComputes() {
        let now = Date()
        let calendar = Calendar.current
        let todayMetric = makeMetric(wordCount: 150, audioDuration: 60)
        todayMetric.timestamp = now
        let alsoToday = makeMetric(wordCount: 200, audioDuration: 60)
        alsoToday.timestamp = calendar.startOfDay(for: now)
        let yesterday = makeMetric(wordCount: 999, audioDuration: 999)
        yesterday.timestamp = calendar.startOfDay(for: now).addingTimeInterval(-1)

        let today = HistoryStats.computeToday(from: [todayMetric, alsoToday, yesterday],
                                              now: now, calendar: calendar)
        XCTAssertEqual(today.words, 350)
        // 350 words over 120s => 175 wpm.
        XCTAssertEqual(today.avgWPM, 175, accuracy: 0.0001)
        XCTAssertEqual(today.dictationSeconds, 120, accuracy: 0.0001)
        XCTAssertEqual(today.sessions, 2)
    }

    func test_computeToday_empty_isZeroNoDivideByZero() {
        let today = HistoryStats.computeToday(from: [])
        XCTAssertEqual(today, HistoryStats.Today(words: 0, avgWPM: 0, dictationSeconds: 0, sessions: 0))
    }

    func test_computeToday_excludesFutureDatedMetrics() {
        let now = Date()
        let calendar = Calendar.current
        let today = makeMetric(wordCount: 100, audioDuration: 60)
        today.timestamp = now
        let tomorrow = makeMetric(wordCount: 500, audioDuration: 500)
        // Calendar arithmetic, not +86,400s — a DST day would false-fail that.
        tomorrow.timestamp = calendar.date(byAdding: .day, value: 1,
                                           to: calendar.startOfDay(for: now))!

        let stats = HistoryStats.computeToday(from: [today, tomorrow], now: now, calendar: calendar)
        XCTAssertEqual(stats.words, 100, "future-dated metrics must not count as today")
        XCTAssertEqual(stats.sessions, 1)
    }
}
