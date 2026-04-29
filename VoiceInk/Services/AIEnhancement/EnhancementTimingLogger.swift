import Foundation
import os

/// W11.D enhancement timing telemetry.
///
/// Append-only CSV at `{ApplicationSupport}/{bundle-id}/enhancement-timings.csv`.
/// One row per enhancement (success, timedOut, cancelled, error). Used to
/// empirically measure perf impact of W11.A fixes (and later W11.B / W11.C).
///
/// Schema (header on first write):
/// ```
/// timestamp,modelId,promptMode,inputChars,outputChars,prepSeconds,ttftSeconds,genSeconds,totalSeconds,gapSinceLastSeconds,outcome
/// ```
///
/// Thread-safe via actor isolation. I/O failures are swallowed (logged via
/// `os_log` but never propagated) — telemetry never breaks the host app.
actor EnhancementTimingLogger {
    static let shared = EnhancementTimingLogger()

    enum Outcome: String {
        case success
        case timedOut
        case cancelled
        case error
    }

    /// Future-compatible: `kvCacheReuse` (W11.A3 follow-up), `afm` (W11.B
    /// Apple Foundation Models), `specDecode` (W11.C speculative decoding).
    enum PromptMode: String {
        case standard
        case fastPath
        case kvCacheReuse
        case afm
        case specDecode
    }

    private static let osLogger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "EnhancementTimingLogger"
    )

    private static let header =
        "timestamp,modelId,promptMode,inputChars,outputChars,prepSeconds,ttftSeconds,genSeconds,totalSeconds,gapSinceLastSeconds,outcome\n"

    /// Wall-clock end of the previous enhancement. Intra-session only
    /// (NOT persisted across launches — gap is intra-session per spec).
    private var lastEnhanceEnd: Date?

    /// ISO 8601 with seconds + local timezone offset (e.g. `2026-04-30T03:47:12+0530`).
    /// `XXXX` produces the no-colon offset form shown in the spec example.
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXX"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    /// Resolves the CSV destination URL. Creates the parent directory if
    /// missing. `nonisolated` so UI can call it without awaiting the actor.
    nonisolated static func csvURL() -> URL {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        let bundle = Bundle.main.bundleIdentifier ?? "com.prakashjoshipax.voiceink"
        let dir = appSupport.appendingPathComponent(bundle, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("enhancement-timings.csv")
    }

    /// Append one row. All time fields are seconds (Double) — empty string
    /// when nil (e.g. cold-fail before generation reached prep stage).
    func record(
        modelId: String,
        promptMode: PromptMode,
        inputChars: Int,
        outputChars: Int,
        prepSeconds: Double?,
        ttftSeconds: Double?,
        genSeconds: Double?,
        totalSeconds: Double,
        startedAt: Date,
        outcome: Outcome
    ) {
        let url = Self.csvURL()
        let now = Date()
        let gap: Double? = lastEnhanceEnd.map { startedAt.timeIntervalSince($0) }
        lastEnhanceEnd = now

        let timestamp = Self.timestampFormatter.string(from: startedAt)
        let row = [
            timestamp,
            csvEscape(modelId),
            promptMode.rawValue,
            String(inputChars),
            String(outputChars),
            formatSeconds(prepSeconds),
            formatSeconds(ttftSeconds),
            formatSeconds(genSeconds),
            formatSeconds(totalSeconds),
            formatSeconds(gap),
            outcome.rawValue,
        ].joined(separator: ",") + "\n"

        appendRow(row, to: url)
    }

    private func appendRow(_ row: String, to url: URL) {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: url.path) {
                try (Self.header + row).write(to: url, atomically: false, encoding: .utf8)
                return
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = row.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            Self.osLogger.warning(
                "🦾 timing-log write failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func formatSeconds(_ value: Double?) -> String {
        guard let v = value else { return "" }
        return String(format: "%.4f", v)
    }

    private func csvEscape(_ s: String) -> String {
        // modelIds contain `/` which is CSV-safe, but quote defensively if any
        // delimiter / quote / newline sneaks in.
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }
}
