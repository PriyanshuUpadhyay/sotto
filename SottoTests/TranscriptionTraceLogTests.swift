import Testing
import Foundation
@testable import Sotto

@Suite struct TranscriptionTraceLogTests {
    /// Build a JSONL line matching the on-disk entry format.
    private func line(ts: Date, render: String) -> String {
        let obj: [String: Any] = ["ts": ts.timeIntervalSince1970, "render": render]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8)!
    }

    @Test("keptLines drops entries older than cutoff, keeps newer ones")
    func dropsOld() {
        let cutoff = Date(timeIntervalSince1970: 1_000_000)
        let old = line(ts: Date(timeIntervalSince1970: 999_999), render: "old")
        let new = line(ts: Date(timeIntervalSince1970: 1_000_001), render: "new")

        let kept = TranscriptionTraceLog.keptLines([old, new], cutoff: cutoff)

        #expect(kept == [new])
    }

    @Test("keptLines keeps an entry exactly at cutoff (>= cutoff)")
    func keepsAtCutoff() {
        let cutoff = Date(timeIntervalSince1970: 1_000_000)
        let atCutoff = line(ts: cutoff, render: "edge")

        let kept = TranscriptionTraceLog.keptLines([atCutoff], cutoff: cutoff)

        #expect(kept == [atCutoff])
    }

    @Test("keptLines drops malformed lines without crashing, preserves survivor order")
    func dropsMalformed() {
        let cutoff = Date(timeIntervalSince1970: 1_000_000)
        let a = line(ts: Date(timeIntervalSince1970: 1_000_010), render: "a")
        let b = line(ts: Date(timeIntervalSince1970: 1_000_020), render: "b")
        let garbage = "{ not valid json"

        let kept = TranscriptionTraceLog.keptLines([a, garbage, b], cutoff: cutoff)

        #expect(kept == [a, b])
    }

    @Test("append writes the rendered trace to disk and prunes stale entries")
    func appendRoundTrip() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("trace-log-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let log = TranscriptionTraceLog(directory: dir)
        let file = dir.appendingPathComponent("pipeline-trace.jsonl")

        // Seed a >7-day-old entry directly so the next append must prune it.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let staleTs = Date().addingTimeInterval(-TranscriptionTraceLog.retention - 60).timeIntervalSince1970
        let staleLine = String(data: try JSONSerialization.data(
            withJSONObject: ["ts": staleTs, "render": "stale"]), encoding: .utf8)!
        try (staleLine + "\n").write(to: file, atomically: true, encoding: .utf8)

        await log.appendAndWait("fresh trace")

        let contents = try String(contentsOf: file, encoding: .utf8)
        #expect(contents.contains("fresh trace"))
        #expect(!contents.contains("stale"))
    }
}
