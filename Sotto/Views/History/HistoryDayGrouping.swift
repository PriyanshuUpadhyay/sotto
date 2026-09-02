import Foundation

/// Chunks the History list into the calendar days it draws section labels for
/// (`TODAY` / `YESTERDAY` / `5 JAN`, per `design-mockups/02-main-app.html`).
enum HistoryDayGrouping {
    /// One contiguous run of rows that share a calendar day.
    struct Section<Row> {
        let day: Date
        let rows: [Row]
    }

    /// Chunk by `startOfDay`, preserving order. Callers must pass the WHOLE
    /// assembled list, never a single page: a day straddles a "Load More"
    /// boundary and has to grow its section rather than start a second one
    /// carrying the same label.
    static func sections<Row>(_ rows: [Row],
                              calendar: Calendar = .current,
                              date: (Row) -> Date) -> [Section<Row>] {
        var sections: [Section<Row>] = []
        var currentDay: Date?
        var currentRows: [Row] = []

        for row in rows {
            let day = calendar.startOfDay(for: date(row))
            if day != currentDay {
                if let currentDay { sections.append(Section(day: currentDay, rows: currentRows)) }
                currentDay = day
                currentRows = []
            }
            currentRows.append(row)
        }
        if let currentDay { sections.append(Section(day: currentDay, rows: currentRows)) }
        return sections
    }

    /// Display-ready (uppercased) section label for a day.
    static func label(for day: Date,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        if calendar.isDate(day, inSameDayAs: today) { return "TODAY" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "YESTERDAY"
        }
        return day.formatted(.dateTime.day().month(.abbreviated)).uppercased()
    }
}
