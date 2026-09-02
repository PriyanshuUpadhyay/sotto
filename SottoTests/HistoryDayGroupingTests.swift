import XCTest
@testable import Sotto

/// F-flow-13 — History groups its rows by calendar day and labels each run.
final class HistoryDayGroupingTests: XCTestCase {

    /// Fixed zone so "just before midnight" means the same thing everywhere.
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: - Labels

    func test_label_today() {
        let now = date(2026, 1, 5, 14, 32)
        let today = calendar.startOfDay(for: now)
        XCTAssertEqual(HistoryDayGrouping.label(for: today, now: now, calendar: calendar), "TODAY")
    }

    func test_label_yesterday() {
        let now = date(2026, 1, 5, 14, 32)
        let yesterday = calendar.startOfDay(for: date(2026, 1, 4, 18, 24))
        XCTAssertEqual(HistoryDayGrouping.label(for: yesterday, now: now, calendar: calendar), "YESTERDAY")
    }

    func test_label_olderDay_isNeitherTodayNorYesterday() {
        let now = date(2026, 1, 5, 14, 32)
        let older = calendar.startOfDay(for: date(2025, 12, 28, 9, 0))
        let label = HistoryDayGrouping.label(for: older, now: now, calendar: calendar)
        XCTAssertFalse(label.isEmpty)
        XCTAssertNotEqual(label, "TODAY")
        XCTAssertNotEqual(label, "YESTERDAY")
    }

    /// 23:59 is still "yesterday" a minute later, not "today" — the label keys
    /// off the calendar day, never off an elapsed-hours window.
    func test_label_justBeforeMidnight_isYesterdayOnTheNextDay() {
        let beforeMidnight = date(2026, 1, 4, 23, 59)
        let afterMidnight = date(2026, 1, 5, 0, 1)
        let day = calendar.startOfDay(for: beforeMidnight)
        XCTAssertEqual(HistoryDayGrouping.label(for: day, now: beforeMidnight, calendar: calendar), "TODAY")
        XCTAssertEqual(HistoryDayGrouping.label(for: day, now: afterMidnight, calendar: calendar), "YESTERDAY")
    }

    // MARK: - Chunking

    func test_sections_chunkByDayPreservingOrder() {
        let stamps = [
            date(2026, 1, 5, 14, 32),
            date(2026, 1, 5, 9, 51),
            date(2026, 1, 4, 18, 24),
            date(2025, 12, 28, 9, 0),
        ]
        let sections = HistoryDayGrouping.sections(stamps, calendar: calendar) { $0 }

        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].rows, [stamps[0], stamps[1]])
        XCTAssertEqual(sections[1].rows, [stamps[2]])
        XCTAssertEqual(sections[2].rows, [stamps[3]])
        XCTAssertEqual(sections[0].day, calendar.startOfDay(for: stamps[0]))
    }

    /// A day that straddles a "Load More" boundary must grow its section, not
    /// emit a second one carrying the same label.
    func test_sections_dayStraddlingAPageBoundaryGrowsOneSection() {
        let firstPage = [date(2026, 1, 5, 14, 32), date(2026, 1, 5, 9, 51)]
        let secondPage = [date(2026, 1, 5, 8, 10), date(2026, 1, 4, 18, 24)]

        let sections = HistoryDayGrouping.sections(firstPage + secondPage, calendar: calendar) { $0 }

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].rows.count, 3)
        XCTAssertEqual(sections[1].rows.count, 1)
    }

    func test_sections_empty() {
        XCTAssertTrue(HistoryDayGrouping.sections([Date](), calendar: calendar) { $0 }.isEmpty)
    }

    /// Midnight is the boundary: 23:59 and 00:01 are two sections.
    func test_sections_midnightBoundarySplits() {
        let stamps = [date(2026, 1, 5, 0, 1), date(2026, 1, 4, 23, 59)]
        let sections = HistoryDayGrouping.sections(stamps, calendar: calendar) { $0 }
        XCTAssertEqual(sections.count, 2)
    }
}
