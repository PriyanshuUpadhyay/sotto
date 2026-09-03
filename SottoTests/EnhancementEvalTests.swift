import Testing
import Foundation
import SwiftData
@testable import Sotto

/// Offline quality + latency eval for the AI-enhancement path. Drives the real
/// production seam — `AIEnhancementService.enhance(_:)` — so every row pays for
/// the same prompt assembly, AFM call, output filter, `stripPreamble`,
/// `VerbatimWordGuard`, repair guard (hardened retry + deterministic fallback)
/// and `AppCategory.applyMechanics` the app uses.
///
/// Every row is a real on-device model call, so `make test` never runs it: the
/// gate is the run-config file `make eval` writes. Results land under
/// `eval/results/`.
@MainActor
@Suite(.serialized)
struct EnhancementEvalTests {

    // MARK: - Fixture

    private struct Item: Decodable {
        let id: String
        let raw: String
        let gold: String
        let tags: [String]
        let control: Bool
        let app_category: String
    }

    private struct Row: Encodable {
        let id: String
        let dataset: String
        let tags: [String]
        let control: Bool
        let appCategory: String
        let raw: String
        let gold: String
        let output: String
        let exact: Bool
        let distance: Double
        let changedControl: Bool
        let guardOutcome: String
        let seconds: Double
        let promptChars: Int
        let error: String?
    }

    private struct DatasetReport: Encodable {
        let dataset: String
        let items: Int
        let exactMatchRate: Double
        let distanceMean: Double
        let distanceP90: Double
        let controls: Int
        let unwantedChangeRate: Double
        let tagPassRate: [String: Double]
        let guardOutcomes: [String: Int]
        let errors: Int
        let latencyP50: Double
        let latencyP90: Double
        let latencyMax: Double
        let promptCharsMean: Int
        let failures: [Row]
    }

    private struct RunReport: Encodable {
        let label: String
        let timestamp: String
        let guidedGeneration: Bool
        let datasets: [DatasetReport]
    }

    // MARK: - Text metrics

    /// Whitespace + quote normalisation. Curly marks fold to straight so a
    /// correct cleanup is not scored down on apostrophe style; blank-line runs
    /// collapse to one so paragraph cues stay comparable.
    nonisolated static func normalize(_ s: String) -> String {
        var t = s
        for (a, b) in [("\u{2019}", "'"), ("\u{2018}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\"")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        var lines: [String] = []
        for line in t.components(separatedBy: .newlines) {
            let squeezed = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            if squeezed.isEmpty, lines.last == "" { continue }
            lines.append(squeezed)
        }
        while lines.first == "" { lines.removeFirst() }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    nonisolated private static func words(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }

    /// Word-level Levenshtein, normalised by the gold word count.
    nonisolated static func wordDistance(_ output: String, gold: String) -> Double {
        let a = words(normalize(output))
        let b = words(normalize(gold))
        guard !b.isEmpty else { return a.isEmpty ? 0 : 1 }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        let distance = a.isEmpty ? b.count : prev[b.count]
        return Double(distance) / Double(b.count)
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = max(1, Int((p * Double(sorted.count)).rounded(.up)))
        return sorted[min(rank, sorted.count) - 1]
    }

    // MARK: - Environment

    /// Repo root derived from this file's compile-time path (`SottoTests/…`).
    /// `xcodebuild test` gives the test bundle neither the invoking shell's
    /// working directory nor, reliably, its environment, so neither can locate
    /// the fixtures.
    nonisolated static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Written by `make eval` immediately before the run and deleted after it,
    /// so the eval is inert under `make test` even if `SOTTO_EVAL` leaks in.
    nonisolated static let runConfigURL = repoRoot.appendingPathComponent("eval/results/.eval-run.json")

    /// `guided` is absent unless `make eval` was given `GUIDED=`. Absent means
    /// "run the app's own default", which is what a plain `make eval` measures.
    private struct RunConfig: Decodable {
        let label: String
        let guided: Bool?
        /// Which fixture to score: `eval` (the default synthetic set), `dev`
        /// (the tuning set), or `heldout` (touched once, at the end).
        let set: String?
    }

    /// The fixture file and report name for a `SET=` value. Unknown values are
    /// rejected by `make eval` and again here, so a typo can never silently
    /// score the wrong file.
    private static let datasetFiles: [String: (name: String, file: String)] = [
        "eval": ("synthetic", "enhancement-eval.jsonl"),
        "dev": ("dev", "enhancement-dev.jsonl"),
        "heldout": ("heldout", "enhancement-heldout.jsonl"),
    ]

    nonisolated static var isEvalRun: Bool {
        FileManager.default.fileExists(atPath: runConfigURL.path)
            && ProcessInfo.processInfo.environment["SOTTO_EVAL"] != "0"
    }

    private static func bundleID(for category: String) -> String {
        switch category {
        case "email": return "com.apple.mail"
        case "workMessaging": return "com.tinyspeck.slackmacgap"
        case "personalMessaging": return "com.apple.MobileSMS"
        default: return "com.example.editor"
        }
    }

    private static func container() -> ModelContainer {
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Run

    @Test(.enabled(if: EnhancementEvalTests.isEvalRun))
    func runEnhancementEval() async throws {
        let root = Self.repoRoot
        let dataDir = root.appendingPathComponent("eval/data")
        let resultsDir = root.appendingPathComponent("eval/results")
        try FileManager.default.createDirectory(at: resultsDir, withIntermediateDirectories: true)

        let config = try JSONDecoder().decode(RunConfig.self, from: Data(contentsOf: Self.runConfigURL))
        let label = config.label
        // The label becomes a path component under eval/results and a result
        // filename. `make eval` already rejects anything else; this is the same
        // gate for a run started by hand.
        try #require(label.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
                     "label must match [A-Za-z0-9._-]+")
        try #require(!label.contains(".."), "label must not contain '..'")
        // Keep the run's AFM timing rows out of the user's Application Support.
        setenv("SOTTO_TIMINGS_DIR", resultsDir.appendingPathComponent("\(label)-timings").path, 1)

        let setName = config.set ?? "eval"
        let chosen = try #require(Self.datasetFiles[setName], "SET must be one of eval, dev, heldout")
        var datasets: [(name: String, url: URL)] = [
            (chosen.name, dataDir.appendingPathComponent(chosen.file))
        ]
        let localURL = dataDir.appendingPathComponent("local/history-dictations.jsonl")
        if FileManager.default.fileExists(atPath: localURL.path) {
            datasets.append(("history", localURL))
        }

        // Deterministic context: no clipboard, no screen OCR, no AX selection —
        // only the Swift-computed active-app category varies, per fixture row.
        let defaults = UserDefaults.standard
        let restore: [String: Any?] = [
            "useClipboardContext": defaults.object(forKey: "useClipboardContext"),
            "useScreenCaptureContext": defaults.object(forKey: "useScreenCaptureContext"),
            "useActiveAppContext": defaults.object(forKey: "useActiveAppContext"),
            "EnhancementGuidedGeneration": defaults.object(forKey: "EnhancementGuidedGeneration"),
        ]
        defer {
            for (key, value) in restore {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(false, forKey: "useClipboardContext")
        defaults.set(false, forKey: "useScreenCaptureContext")
        defaults.set(true, forKey: "useActiveAppContext")
        if let override = config.guided {
            defaults.set(override, forKey: "EnhancementGuidedGeneration")
        } else {
            defaults.removeObject(forKey: "EnhancementGuidedGeneration")
        }
        let guided = if #available(macOS 26.0, *) { AFMProvider.guidedGenerationEnabled } else { false }

        let modelContainer = Self.container()
        let service = AIEnhancementService(modelContext: modelContainer.mainContext)
        service.selectedTextProvider = { nil }
        try #require(service.isConfigured, "AFM is unavailable — the eval needs a real on-device model.")

        var reports: [DatasetReport] = []
        for dataset in datasets {
            reports.append(try await run(dataset: dataset.name, url: dataset.url, service: service))
        }

        let stamp = Self.timestamp()
        let report = RunReport(label: label, timestamp: stamp, guidedGeneration: guided, datasets: reports)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: resultsDir.appendingPathComponent("\(stamp)-\(label).json"))
        try Self.markdown(report).write(
            to: resultsDir.appendingPathComponent("\(stamp)-\(label).md"), atomically: true, encoding: .utf8)

        _ = modelContainer
    }

    private func run(dataset: String, url: URL, service: AIEnhancementService) async throws -> DatasetReport {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        let items: [Item] = try text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try decoder.decode(Item.self, from: Data($0.utf8)) }

        var rows: [Row] = []
        for item in items {
            let bundleID = Self.bundleID(for: item.app_category)
            service.frontmostAppProvider = { (name: item.app_category, bundleID: bundleID) }

            let started = Date()
            var output = ""
            var failure: String? = nil
            do {
                let (enhanced, _, _) = try await service.enhance(item.raw)
                output = enhanced
            } catch {
                failure = "\(error)"
            }
            let seconds = Date().timeIntervalSince(started)
            let promptChars = (service.lastSystemMessageSent?.count ?? 0) + (service.lastUserMessageSent?.count ?? 0)

            let exact = Self.normalize(output) == Self.normalize(item.gold)
            let distance = Self.wordDistance(output, gold: item.gold)
            rows.append(Row(
                id: item.id, dataset: dataset, tags: item.tags, control: item.control,
                appCategory: item.app_category, raw: item.raw,
                gold: item.gold, output: output,
                exact: exact, distance: distance,
                changedControl: item.control && Self.normalize(output) != Self.normalize(item.raw),
                // `performEnhance` throws before it publishes an outcome, so a
                // failed row would otherwise inherit the previous row's verdict
                // and be counted twice. Error and guard outcome are exclusive.
                guardOutcome: failure == nil ? service.lastGuardOutcome.rawValue : "error",
                seconds: seconds, promptChars: promptChars, error: failure))
        }

        let scored = rows.filter { $0.error == nil }
        let controls = rows.filter { $0.control }
        var tagPass: [String: Double] = [:]
        for tag in Set(rows.flatMap(\.tags)).sorted() {
            let tagged = rows.filter { $0.tags.contains(tag) }
            let passed = tagged.filter { $0.error == nil && ($0.exact || $0.distance <= 0.05) }.count
            tagPass[tag] = tagged.isEmpty ? 0 : Double(passed) / Double(tagged.count)
        }
        var outcomes: [String: Int] = ["error": 0]
        for outcome in EnhancementGuardOutcome.allCases { outcomes[outcome.rawValue] = 0 }
        for row in rows { outcomes[row.guardOutcome, default: 0] += 1 }

        let distances = scored.map(\.distance)
        let latencies = rows.map(\.seconds)
        return DatasetReport(
            dataset: dataset,
            items: rows.count,
            exactMatchRate: rows.isEmpty ? 0 : Double(rows.filter(\.exact).count) / Double(rows.count),
            distanceMean: distances.isEmpty ? 0 : distances.reduce(0, +) / Double(distances.count),
            distanceP90: Self.percentile(distances, 0.9),
            controls: controls.count,
            unwantedChangeRate: controls.isEmpty ? 0 : Double(controls.filter(\.changedControl).count) / Double(controls.count),
            tagPassRate: tagPass,
            guardOutcomes: outcomes,
            errors: rows.filter { $0.error != nil }.count,
            latencyP50: Self.percentile(latencies, 0.5),
            latencyP90: Self.percentile(latencies, 0.9),
            latencyMax: latencies.max() ?? 0,
            promptCharsMean: rows.isEmpty ? 0 : rows.map(\.promptChars).reduce(0, +) / rows.count,
            failures: rows.filter { !$0.exact }.sorted { $0.distance > $1.distance })
    }

    // MARK: - Report

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    private static func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
    private static func num(_ v: Double) -> String { String(format: "%.3f", v) }

    private static func markdown(_ report: RunReport) -> String {
        var out = "# Enhancement eval — \(report.label)\n\n"
        out += "- run: `\(report.timestamp)`\n- guided generation: `\(report.guidedGeneration)`\n\n"
        for d in report.datasets {
            out += "## \(d.dataset) (\(d.items) items)\n\n"
            out += "| metric | value |\n|---|---|\n"
            out += "| exact match | \(pct(d.exactMatchRate)) |\n"
            out += "| word distance mean | \(num(d.distanceMean)) |\n"
            out += "| word distance p90 | \(num(d.distanceP90)) |\n"
            out += "| unwanted change on controls (\(d.controls)) | \(pct(d.unwantedChangeRate)) |\n"
            out += "| latency p50 / p90 / max | \(num(d.latencyP50)) / \(num(d.latencyP90)) / \(num(d.latencyMax)) s |\n"
            out += "| prompt chars (mean) | \(d.promptCharsMean) |\n"
            out += "| errors | \(d.errors) |\n\n"
            out += "### guard outcomes\n\n| outcome | count |\n|---|---|\n"
            for (k, v) in d.guardOutcomes.sorted(by: { $0.key < $1.key }) { out += "| \(k) | \(v) |\n" }
            out += "\n### per-tag pass rate (exact or distance ≤ 0.05)\n\n| tag | pass |\n|---|---|\n"
            for (k, v) in d.tagPassRate.sorted(by: { $0.key < $1.key }) { out += "| \(k) | \(pct(v)) |\n" }
            out += "\n### failures (\(d.failures.count))\n\n"
            for f in d.failures {
                out += "**\(f.id)** — d=\(num(f.distance)) tags=\(f.tags.joined(separator: ",")) guard=\(f.guardOutcome)\n"
                out += "```\nraw:    \(f.raw)\noutput: \(f.output)\ngold:   \(f.gold)\n```\n"
                if let e = f.error { out += "error: `\(e)`\n" }
                out += "\n"
            }
        }
        return out
    }
}
