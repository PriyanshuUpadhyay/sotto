import SwiftUI
import SwiftData

/// Four calm stat cells at the top of History: WORDS TODAY / AVG WPM /
/// DICTATION TIME / SESSIONS. SessionMetric lives in the separate stats.store
/// container, unreachable from the environment modelContext — fetched manually
/// from `StatsModelContainerProvider` (never `@Query`) and refreshed on appear
/// + on `.sessionMetricsDidChange`, mirroring InlineHistoryView.
struct HistoryStatsBand: View {
    @State private var today = HistoryStats.Today(words: 0, avgWPM: 0, dictationSeconds: 0, sessions: 0)

    var body: some View {
        HStack(spacing: 10) {
            statCell(value: today.words.formatted(), label: "Words Today")
            statCell(value: String(format: "%.0f", today.avgWPM), label: "Avg WPM")
            statCell(value: Self.formattedDuration(today.dictationSeconds), label: "Dictation Time")
            statCell(value: "\(today.sessions)", label: "Sessions")
        }
        .padding(.horizontal, 16)
        .padding(.top, 34)
        .background(Theme.canvas)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .sessionMetricsDidChange)) { _ in
            reload()
        }
        // Rolls the band over at midnight while the window stays open.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            reload()
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.ui(24, weight: .semibold))
                .tracking(-0.4)
                .tabularNumbers()
                .foregroundStyle(Palette.inkPrimary)
            Text(label.uppercased())
                .font(.microlabel(11))
                .tracking(0.18 * 11)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, 15)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Theme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func reload() {
        guard let container = StatsModelContainerProvider.shared.modelContainer else { return }
        let ctx = ModelContext(container)
        // Fetch only the current day window — the store holds all-time metrics
        // and this runs on every session notification.
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? .distantFuture
        let descriptor = FetchDescriptor<SessionMetric>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end }
        )
        let metrics = (try? ctx.fetch(descriptor)) ?? []
        today = HistoryStats.computeToday(from: metrics, now: now)
    }

    static func formattedDuration(_ seconds: Double) -> String {
        guard seconds >= 1 else { return "0m" }
        let minutes = Int(seconds / 60)
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        if minutes >= 1 { return "\(minutes)m" }
        return "\(Int(seconds))s"
    }
}
