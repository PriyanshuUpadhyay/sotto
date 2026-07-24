import Foundation
import OSLog

/// Durable sink for rendered `TranscriptionTrace` records. Each call appends one
/// JSONL line and prunes entries older than `retention`, so the file is a rolling
/// 7-day window (os_log retention is OS-managed and can't guarantee a TTL, so we
/// own the file). Fire-and-forget off the main actor — never blocks the paste path,
/// fails soft on any I/O error. A plain sink, no UI. An `actor` so the
/// read-modify-write of the shared file is serialized: two dictations in quick
/// succession can't lose-update each other's appended line.
actor TranscriptionTraceLog {
    static let shared = TranscriptionTraceLog()
    static let retention: TimeInterval = 7 * 24 * 60 * 60   // 7 days

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "TranscriptionTraceLog")
    private let directory: URL

    private var fileURL: URL { directory.appendingPathComponent("pipeline-trace.jsonl") }

    /// Default base dir mirrors TranscriptionAutoCleanupService, under a new Logs/ subfolder.
    private static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppSupport.directoryName)
            .appendingPathComponent("Logs")
    }

    init(directory: URL = TranscriptionTraceLog.defaultDirectory) {
        self.directory = directory
    }

    private struct Entry: Codable { let ts: Double; let render: String }

    /// Append one rendered trace as a JSONL line, then prune stale entries.
    /// Returns immediately; the work runs detached so the @MainActor pipeline never blocks.
    /// `nonisolated` so the synchronous call site needs no await; the detached Task then
    /// hops onto the actor, where `appendAndWait` is serialized with all other appends.
    nonisolated func append(_ rendered: String) {
        Task.detached(priority: .utility) { [weak self] in
            await self?.appendAndWait(rendered)
        }
    }

    /// The actual write+prune, awaitable for tests. Fail-soft: any throw is logged, never propagated.
    func appendAndWait(_ rendered: String) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let newLine = String(decoding: try JSONEncoder().encode(
                Entry(ts: Date().timeIntervalSince1970, render: rendered)), as: UTF8.self)

            // Distinguish "no file yet" (start fresh) from "read failed" — a transient
            // read error must NOT wipe 7 days of history. Only file-absent yields [];
            // a real read throw is caught below and skips the write, preserving the file.
            let existing: [String]
            if FileManager.default.fileExists(atPath: fileURL.path) {
                existing = try String(contentsOf: fileURL, encoding: .utf8)
                    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            } else {
                existing = []
            }

            let cutoff = Date().addingTimeInterval(-Self.retention)
            let kept = Self.keptLines(existing + [newLine], cutoff: cutoff)

            try (kept.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to append trace: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// PURE: keep lines that decode and whose `ts` is >= cutoff, preserving order.
    /// Disk-free and side-effect-free — the unit-tested core.
    static func keptLines(_ lines: [String], cutoff: Date) -> [String] {
        let cutoffEpoch = cutoff.timeIntervalSince1970
        return lines.filter { line in
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return false }
            return entry.ts >= cutoffEpoch
        }
    }
}
