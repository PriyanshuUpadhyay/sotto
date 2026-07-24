import Foundation
import SwiftData
import os

/// Developer-run multi-model transcription sweep. Replays each stored
/// `Transcription` row's saved WAV through every usable transcription model
/// in `transcriptionModelManager.usableModels`, then writes a markdown report
/// with side-by-side outputs + per-model latency. Used to qualitatively decide
/// which transcription models to keep or drop.
///
/// Not part of CI — depends on user-side downloaded model state and is wall-clock
/// heavy (N models × M recordings sequential transcriptions).
@MainActor
enum TranscriptionEvalHarness {

    private static let logger = Logger(
        subsystem: OSLogSubsystems.app,
        category: "TranscriptionEvalHarness"
    )

    struct PerModelResult {
        let modelId: String
        let displayName: String
        let outcome: Outcome
        let durationSeconds: TimeInterval

        enum Outcome {
            case success(rawASRText: String, finalText: String, metrics: TranscriptionTextMetrics.ErrorRates?)
            case failure(reason: String)
        }
    }

    struct RecordingResult {
        let transcriptionId: UUID
        let audioPath: String
        let audioDuration: TimeInterval
        let originalModelName: String?
        let originalText: String
        let referenceTranscript: String?
        let perModel: [PerModelResult]
    }

    /// Runs the sweep. Returns the URL of the written markdown report.
    static func run(
        whisperModelManager: WhisperModelManager,
        fluidAudioModelManager: FluidAudioModelManager,
        transcriptionModelManager: TranscriptionModelManager,
        modelContext: ModelContext,
        maxRecordings: Int = 20,
        referenceTranscriptProvider: ((Transcription) -> String?)? = nil
    ) async throws -> URL {
        let serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: whisperModelManager,
            modelsDirectory: whisperModelManager.modelsDirectory,
            modelContext: modelContext
        )
        defer { Task { await serviceRegistry.cleanup() } }

        // Only local models — sweep cost is dominated by inference;
        // cloud rows would charge the user money.
        let localProviders: Set<ModelProvider> = [.whisper, .fluidAudio, .nativeApple]
        let candidates = transcriptionModelManager.usableModels.filter { model in
            localProviders.contains(model.provider)
        }
        guard !candidates.isEmpty else {
            throw NSError(domain: "TranscriptionEvalHarness", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                            "No usable local transcription models — download at least one and retry."])
        }

        let rows = try modelContext.fetch(
            FetchDescriptor<Transcription>(sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)])
        )

        var results: [RecordingResult] = []

        for row in rows {
            if results.count >= maxRecordings { break }
            // Transcription.audioFileURL is stored as URL.absoluteString
            // (`file:///Users/.../uuid.wav`) per SottoEngine.swift:129 +
            // AudioFileTranscriptionService.swift. Defensive against legacy
            // rows that may store a raw path.
            guard let urlString = row.audioFileURL, !urlString.isEmpty else { continue }
            let audioURL: URL
            if let parsed = URL(string: urlString), parsed.isFileURL {
                audioURL = parsed
            } else {
                audioURL = URL(fileURLWithPath: urlString)
            }
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                continue
            }

            var perModelResults: [PerModelResult] = []
            let referenceTranscript = referenceTranscriptProvider?(row)
            for model in candidates {
                let start = Date()
                do {
                    let text = try await transcribeForHarness(
                        audioURL: audioURL,
                        model: model,
                        serviceRegistry: serviceRegistry
                    )
                    let dur = Date().timeIntervalSince(start)
                    let metrics = referenceTranscript.map {
                        TranscriptionTextMetrics.errorRates(reference: $0, hypothesis: text)
                    }
                    perModelResults.append(.init(
                        modelId: model.name,
                        displayName: model.displayName,
                        outcome: .success(rawASRText: text, finalText: text, metrics: metrics),
                        durationSeconds: dur
                    ))
                } catch {
                    let dur = Date().timeIntervalSince(start)
                    perModelResults.append(.init(
                        modelId: model.name,
                        displayName: model.displayName,
                        outcome: .failure(reason: error.localizedDescription),
                        durationSeconds: dur
                    ))
                }
            }

            results.append(.init(
                transcriptionId: row.id,
                audioPath: audioURL.path,
                audioDuration: row.duration,
                originalModelName: row.transcriptionModelName,
                originalText: row.text,
                referenceTranscript: referenceTranscript,
                perModel: perModelResults
            ))
            logger.notice("🦾 transcription-eval: row \(results.count, privacy: .public)/\(maxRecordings, privacy: .public) done")
        }

        let report = generateReport(results: results, candidates: candidates)
        let url = reportURL()
        try report.write(to: url, atomically: true, encoding: .utf8)
        logger.notice("🦾 transcription-eval: wrote \(url.path, privacy: .public) — \(results.count, privacy: .public) recordings × \(candidates.count, privacy: .public) models")
        return url
    }

    private static func transcribeForHarness(
        audioURL: URL,
        model: any TranscriptionModel,
        serviceRegistry: TranscriptionServiceRegistry
    ) async throws -> String {
        guard model.supportsStreaming else {
            return try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
        }

        let session = serviceRegistry.createSession(for: model)
        guard let streamAudioChunk = try await session.prepare(model: model) else {
            return try await session.transcribe(audioURL: audioURL, audioDurationSeconds: nil)
        }

        do {
            let data = try Data(contentsOf: audioURL)
            let pcmStart = min(44, data.count)
            let chunkSize = 3_200 // 100 ms of 16 kHz mono PCM16.
            var offset = pcmStart
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                streamAudioChunk(data.subdata(in: offset..<end))
                offset = end
            }
            return try await session.transcribe(audioURL: audioURL, audioDurationSeconds: nil)
        } catch {
            session.cancel()
            throw error
        }
    }

    private static func generateReport(
        results: [RecordingResult],
        candidates: [any TranscriptionModel]
    ) -> String {
        let timingSummary = aggregateTiming(results: results)

        var lines: [String] = [
            "# Transcription Eval — Multi-Model Sweep",
            "",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "Recordings evaluated: \(results.count)",
            "Models swept: \(candidates.count)",
            "",
            "## Per-model timing summary",
            "",
            "| Model | Mean latency | Successes | Failures |",
            "|---|---|---|---|"
        ]
        for c in candidates {
            let id = c.name
            let mean = timingSummary[id]?.mean ?? 0
            let succ = timingSummary[id]?.successes ?? 0
            let fail = timingSummary[id]?.failures ?? 0
            lines.append("| \(c.displayName) | \(String(format: "%.2fs", mean)) | \(succ) | \(fail) |")
        }
        lines.append("")
        lines.append("---")
        lines.append("")

        for r in results {
            lines.append("### \(r.transcriptionId.uuidString)")
            lines.append("")
            lines.append("- Audio: `\(r.audioPath)` (\(String(format: "%.1f", r.audioDuration))s)")
            lines.append("- Original model: \(r.originalModelName ?? "unknown")")
            if let referenceTranscript = r.referenceTranscript {
                lines.append("- Reference transcript provided: yes")
                lines.append("")
                lines.append("**Reference transcript:**")
                lines.append("")
                lines.append("> \(escape(referenceTranscript))")
            } else {
                lines.append("- Reference transcript provided: no — WER/CER omitted")
            }
            lines.append("")
            lines.append("**Original transcript (in Sotto's saved row):**")
            lines.append("")
            lines.append("> \(escape(r.originalText))")
            lines.append("")
            lines.append("Harness output note: this sweep uses streaming sessions for streaming-capable models and direct batch services for batch models. No enhancement/post-processing stage output is available here, so final output currently matches raw ASR output.")
            lines.append("")
            lines.append("| Model | Latency | WER | CER | Raw ASR output | Final output |")
            lines.append("|---|---|---|---|---|---|")
            for m in r.perModel {
                let latency = String(format: "%.2fs", m.durationSeconds)
                let wer: String
                let cer: String
                let rawASR: String
                let final: String
                switch m.outcome {
                case .success(let rawASRText, let finalText, let metrics):
                    wer = metrics.map { String(format: "%.3f", $0.wordErrorRate) } ?? "—"
                    cer = metrics.map { String(format: "%.3f", $0.characterErrorRate) } ?? "—"
                    rawASR = "`\(escape(rawASRText))`"
                    final = "`\(escape(finalText))`"
                case .failure(let reason):
                    wer = "—"
                    cer = "—"
                    rawASR = "Failed: \(escape(reason))"
                    final = "Failed"
                }
                lines.append("| \(m.displayName) | \(latency) | \(wer) | \(cer) | \(rawASR) | \(final) |")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func aggregateTiming(
        results: [RecordingResult]
    ) -> [String: (mean: TimeInterval, successes: Int, failures: Int)] {
        var bucket: [String: (sum: TimeInterval, count: Int, successes: Int, failures: Int)] = [:]
        for r in results {
            for m in r.perModel {
                var b = bucket[m.modelId] ?? (0, 0, 0, 0)
                b.sum += m.durationSeconds
                b.count += 1
                switch m.outcome {
                case .success: b.successes += 1
                case .failure: b.failures += 1
                }
                bucket[m.modelId] = b
            }
        }
        return bucket.mapValues { v in
            (mean: v.count > 0 ? v.sum / Double(v.count) : 0,
             successes: v.successes,
             failures: v.failures)
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func reportURL() -> URL {
        let dir = EnhancementTimingLogger.csvURL().deletingLastPathComponent()
        let stamp = Int(Date().timeIntervalSince1970)
        return dir.appendingPathComponent("transcription-eval-\(stamp).md")
    }
}
