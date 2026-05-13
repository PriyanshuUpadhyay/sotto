import SwiftUI
import SwiftData

// MARK: - Time filter

enum TimeFilter: String, CaseIterable, Identifiable {
    case last7Days  = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case thisYear   = "This Year"
    case allTime    = "All Time"

    var id: String { rawValue }

    var predicate: Predicate<SessionMetric>? {
        let now = Date()
        switch self {
        case .allTime:
            return nil
        case .last7Days:
            let start = now.addingTimeInterval(-7 * 24 * 3600)
            return #Predicate<SessionMetric> { $0.timestamp >= start }
        case .last30Days:
            let start = now.addingTimeInterval(-30 * 24 * 3600)
            return #Predicate<SessionMetric> { $0.timestamp >= start }
        case .thisYear:
            guard let start = Calendar.current.dateInterval(of: .year, for: now)?.start else { return nil }
            return #Predicate<SessionMetric> { $0.timestamp >= start }
        }
    }
}

// MARK: - Panel shell (owns filter state)

struct ModelPerformancePanel: View {
    @AppStorage("modelPerfPanelFilter") private var filterRaw: String = TimeFilter.last7Days.rawValue
    let onClose: () -> Void

    private var filter: TimeFilter { TimeFilter(rawValue: filterRaw) ?? .last7Days }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    TacticalGlass(shape: Rectangle(), phase: .hidden)
                )
                .overlay(
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 0.5),
                    alignment: .bottom
                )
                .zIndex(1)

            ModelPerformancePanelContent(filter: filter)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("MODEL PERFORMANCE")
                .font(.system(size: 11, design: .monospaced).weight(.bold))
                .tracking(0.16 * 11)
                .foregroundStyle(Color.white.opacity(0.42))
            Spacer()
            Picker("", selection: Binding(get: { filter }, set: { filterRaw = $0.rawValue })) {
                ForEach(TimeFilter.allCases) { f in
                    Text(f.rawValue.uppercased())
                        .font(.system(size: 11, design: .monospaced))
                        .tag(f)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Button(action: onClose) {
                Text("✕")
                    .font(.system(size: 12, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Content (owns @Query, reacts to filter)

private struct ModelPerformancePanelContent: View {
    @Query private var metrics: [SessionMetric]

    init(filter: TimeFilter) {
        if let predicate = filter.predicate {
            _metrics = Query(filter: predicate)
        } else {
            _metrics = Query()
        }
    }

    private var modelStats: [ModelPerformanceStat] {
        var accumulators: [String: ModelPerformanceAccumulator] = [:]
        for metric in metrics {
            guard let name = metric.transcriptionModelName,
                  let processingDuration = metric.transcriptionDuration,
                  processingDuration > 0 else { continue }
            accumulators[name, default: ModelPerformanceAccumulator()].add(
                audioDuration: metric.audioDuration,
                processingDuration: processingDuration
            )
        }
        return accumulators.map { name, acc in acc.stat(named: name) }
            .sorted { $0.avgProcessingTime < $1.avgProcessingTime }
    }

    private var enhancementStats: [EnhancementStat] {
        var accumulators: [String: EnhancementAccumulator] = [:]
        for metric in metrics {
            guard let name = metric.aiEnhancementModelName,
                  let duration = metric.enhancementDuration,
                  duration > 0 else { continue }
            accumulators[name, default: EnhancementAccumulator()].add(duration: duration)
        }
        return accumulators.map { name, acc in acc.stat(named: name) }
            .sorted { $0.avgDuration < $1.avgDuration }
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if modelStats.isEmpty && enhancementStats.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !modelStats.isEmpty {
                        modelsSection
                    }
                    if !enhancementStats.isEmpty {
                        enhancementSection
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.white.opacity(0.42))
            Text("NO DATA FOR THIS PERIOD")
                .font(.system(size: 11, design: .monospaced).weight(.bold))
                .tracking(0.16 * 11)
                .foregroundStyle(Color.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Models grid

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Transcription Models")
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(modelStats) { stat in
                    modelTile(stat)
                }
            }
        }
    }

    private func modelTile(_ stat: ModelPerformanceStat) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(stat.name.uppercased())
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .tracking(0.16 * 10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.primary)
                Text("\(stat.sessionCount) sessions")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Text(String(format: "%.1fx", stat.speedFactor))
                    .font(.system(size: 20, design: .monospaced).weight(.bold))
                    .foregroundStyle(Palette.brandAcid)
                Text(stat.speedFactor >= 1.0 ? "faster than real-time" : "slower than real-time")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
            }

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 0.5)
                .padding(.horizontal, 4)

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(formatDuration(stat.avgAudioDuration))
                        .font(.system(size: 10, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.42))
                    Text("AVG AUDIO")
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(0.16 * 8)
                        .foregroundStyle(Color.white.opacity(0.42).opacity(0.6))
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 0.5, height: 20)

                VStack(spacing: 2) {
                    Text(String(format: "%.2fs", stat.avgProcessingTime))
                        .font(.system(size: 10, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.42))
                    Text("AVG PROC")
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(0.16 * 8)
                        .foregroundStyle(Color.white.opacity(0.42).opacity(0.6))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(
            TacticalGlass(shape: RoundedRectangle(cornerRadius: 2, style: .continuous), phase: .hidden)
        )
    }

    // MARK: - Enhancement Models

    private var enhancementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Enhancement Models")
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(enhancementStats) { stat in
                    enhancementTile(stat)
                }
            }
        }
    }

    private func enhancementTile(_ stat: EnhancementStat) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(stat.name.uppercased())
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .tracking(0.16 * 10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.primary)
                Text("\(stat.sessionCount) sessions")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Text(String(format: "%.2fs", stat.avgDuration))
                    .font(.system(size: 20, design: .monospaced).weight(.bold))
                    .foregroundStyle(Palette.brandAcid)
                Text("avg enhancement time")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
        }
        .padding(12)
        .background(
            TacticalGlass(shape: RoundedRectangle(cornerRadius: 2, style: .continuous), phase: .hidden)
        )
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text("›")
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .foregroundStyle(Palette.brandAcid)
                .accessibilityHidden(true)
            Text(title.uppercased())
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .tracking(0.16 * 10)
                .foregroundStyle(Color.white.opacity(0.42))
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
}

// MARK: - Data models

struct ModelPerformanceStat: Identifiable {
    var id: String { name }
    let name: String
    let sessionCount: Int
    let totalProcessingTime: TimeInterval
    let avgProcessingTime: TimeInterval
    let avgAudioDuration: TimeInterval
    let speedFactor: Double
}

struct ModelPerformanceAccumulator {
    var sessionCount = 0
    var totalProcessingTime: TimeInterval = 0
    var totalAudioDuration: TimeInterval = 0

    mutating func add(audioDuration: TimeInterval, processingDuration: TimeInterval) {
        sessionCount += 1
        totalProcessingTime += processingDuration
        totalAudioDuration += audioDuration
    }

    func stat(named name: String) -> ModelPerformanceStat {
        let safeCount = max(sessionCount, 1)
        let speedFactor = totalProcessingTime > 0 ? totalAudioDuration / totalProcessingTime : 0
        return ModelPerformanceStat(
            name: name,
            sessionCount: sessionCount,
            totalProcessingTime: totalProcessingTime,
            avgProcessingTime: totalProcessingTime / Double(safeCount),
            avgAudioDuration: totalAudioDuration / Double(safeCount),
            speedFactor: speedFactor
        )
    }
}

struct EnhancementStat: Identifiable {
    var id: String { name }
    let name: String
    let sessionCount: Int
    let avgDuration: TimeInterval
}

struct EnhancementAccumulator {
    var sessionCount = 0
    var totalDuration: TimeInterval = 0

    mutating func add(duration: TimeInterval) {
        sessionCount += 1
        totalDuration += duration
    }

    func stat(named name: String) -> EnhancementStat {
        let safeCount = max(sessionCount, 1)
        return EnhancementStat(
            name: name,
            sessionCount: sessionCount,
            avgDuration: totalDuration / Double(safeCount)
        )
    }
}
