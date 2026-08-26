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
/// timestamp,modelId,promptMode,transcriptChars,promptChars,callKind,warmAgeSeconds,outputChars,prepSeconds,ttftSeconds,genSeconds,totalSeconds,gapSinceLastSeconds,outcome,sessionReused
/// ```
/// `promptChars` / `callKind` / `warmAgeSeconds` exist to explain warm TTFT
/// (p50 ~0.71s) against Apple's published ~120ms: `promptChars` separates a
/// prefill cost that scales with prompt size from a fixed per-call floor,
/// `callKind` keeps the hardened-retry and import paths (different prompt
/// sizes, no warm reuse) from polluting the primary-path distribution, and
/// `warmAgeSeconds` tests whether a warm slot decays with age — a TTFT that
/// climbs with warm age means the prefilled prefix isn't surviving until the
/// enhance, not that prefill is slow.
///
/// `sessionReused` is X1/F7 acceptance evidence: whether this call reused a
/// record-start-warmed AFM session (stable instruction key) vs building fresh
/// — before the F7 fix this was near-always `false` once any volatile context
/// (selected text/clipboard/screen/app) differed between warm and enhance.
///
/// A second, separate small CSV (`recordStopToPaste`) captures X1/F6
/// acceptance evidence — end-to-end wall-clock from recording-stop to the
/// enhanced text landing via paste — since that span doesn't fit this
/// per-AFM-call schema (paste happens well after this row is written).
///
/// A third small CSV (`recordStopToPreview`) captures recording-stop to the
/// review-before-paste editor appearing — the system-only portion of the
/// stop→paste span, which otherwise includes the user's review dwell time.
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
        /// AFM declined the prompt via its safety/guardrail filter. Distinct
        /// from `.error` (a hard AFM failure) so the refusal RATE is measurable
        /// from the CSV. There is no second provider — the refusal
        /// surfaces as an enhancement error and there is no follow-up row.
        case safetyRefusal
    }

    /// Which enhancement path produced this row. The three paths have
    /// structurally different prompts and warm-reuse eligibility, so TTFT
    /// percentiles are only comparable within one kind.
    enum CallKind: String {
        /// Normal dictation, first pass — the only path eligible for warm reuse.
        case primary
        /// Repair-guard retry with the hardened prompt (no volatile context).
        case hardenedRetry
        /// File-import re-enhance; runs with generation `-1`, never reuses warm.
        case `import`
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
        subsystem: "com.sotto.Sotto",
        category: "EnhancementTimingLogger"
    )

    private static let header =
        "timestamp,modelId,promptMode,transcriptChars,promptChars,callKind,warmAgeSeconds,outputChars,prepSeconds,ttftSeconds,genSeconds,totalSeconds,gapSinceLastSeconds,outcome,sessionReused\n"

    private static let stopToPasteHeader = "timestamp,stopToPasteSeconds\n"

    private static let stopToPreviewHeader = "timestamp,stopToPreviewSeconds\n"

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
        let bundle = Bundle.main.bundleIdentifier ?? "com.sotto.Sotto"
        let dir = appSupport.appendingPathComponent(bundle, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("enhancement-timings.csv")
    }

    nonisolated static func stopToPasteCSVURL() -> URL {
        csvURL().deletingLastPathComponent().appendingPathComponent("enhancement-stop-to-paste.csv")
    }

    nonisolated static func stopToPreviewCSVURL() -> URL {
        csvURL().deletingLastPathComponent().appendingPathComponent("enhancement-stop-to-preview.csv")
    }

    /// Append one row. All time fields are seconds (Double) — empty string
    /// when nil (e.g. cold-fail before generation reached prep stage).
    /// `transcriptChars` is the raw transcript length, NOT the prompt length —
    /// the prompt wrapper's fixed ~235 chars would swamp any
    /// input-vs-output comparison. `promptChars` is the full prefill size
    /// (system + user prompt) that TTFT actually pays for. `warmAgeSeconds` is
    /// nil unless this call reused a warmed session.
    func record(
        modelId: String,
        promptMode: PromptMode,
        transcriptChars: Int,
        promptChars: Int,
        callKind: CallKind,
        warmAgeSeconds: Double?,
        outputChars: Int,
        prepSeconds: Double?,
        ttftSeconds: Double?,
        genSeconds: Double?,
        totalSeconds: Double,
        startedAt: Date,
        outcome: Outcome,
        sessionReused: Bool
    ) {
        let now = Date()
        let gap: Double? = lastEnhanceEnd.map { startedAt.timeIntervalSince($0) }
        lastEnhanceEnd = now

        let timestamp = Self.timestampFormatter.string(from: startedAt)
        let row = [
            timestamp,
            csvEscape(modelId),
            promptMode.rawValue,
            String(transcriptChars),
            String(promptChars),
            callKind.rawValue,
            formatSeconds(warmAgeSeconds),
            String(outputChars),
            formatSeconds(prepSeconds),
            formatSeconds(ttftSeconds),
            formatSeconds(genSeconds),
            formatSeconds(totalSeconds),
            formatSeconds(gap),
            outcome.rawValue,
            String(sessionReused),
        ].joined(separator: ",") + "\n"

        appendRow(row, header: Self.header, to: Self.csvURL())
    }

    /// X1/F6 acceptance evidence — see the type doc comment. Logged by
    /// `SottoEngine` from stop (`toggleRecord`) to paste (`handleDidPaste`).
    func recordStopToPaste(seconds: TimeInterval) {
        let row = "\(Self.timestampFormatter.string(from: Date())),\(formatSeconds(seconds))\n"
        appendRow(row, header: Self.stopToPasteHeader, to: Self.stopToPasteCSVURL())
    }

    /// See the type doc comment. Logged by `SottoEngine` from stop
    /// (`toggleRecord`) to the review editor presenting (`onPreviewShown`).
    func recordStopToPreview(seconds: TimeInterval) {
        let row = "\(Self.timestampFormatter.string(from: Date())),\(formatSeconds(seconds))\n"
        appendRow(row, header: Self.stopToPreviewHeader, to: Self.stopToPreviewCSVURL())
    }

    private func appendRow(_ row: String, header: String, to url: URL) {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: url.path), !fileStartsWithHeader(header, at: url) {
                // Schema changed (e.g. a column was added) since this file was
                // created — appending under a mismatched header would silently
                // produce a heterogeneous CSV (old rows with N fields, new rows
                // with N+1). Rotate the stale file aside and start fresh rather
                // than corrupt it.
                try rotateAside(url)
            }
            if !fm.fileExists(atPath: url.path) {
                try (header + row).write(to: url, atomically: false, encoding: .utf8)
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

    private func fileStartsWithHeader(_ header: String, at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: header.utf8.count) else { return false }
        return String(data: data, encoding: .utf8) == header
    }

    private func rotateAside(_ url: URL) throws {
        let fm = FileManager.default
        var index = 1
        var candidate = url.deletingPathExtension().appendingPathExtension("old-\(index).csv")
        while fm.fileExists(atPath: candidate.path) {
            index += 1
            candidate = url.deletingPathExtension().appendingPathExtension("old-\(index).csv")
        }
        try fm.moveItem(at: url, to: candidate)
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
