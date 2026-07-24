import Foundation
import os

struct TranscriptionSessionDiagnostics {
    var sessionType: String
    var streamingFinalLength: Int? = nil
    var fallbackReason: String? = nil
}

/// Encapsulates a single recording-to-transcription lifecycle (streaming or file-based).
@MainActor
protocol TranscriptionSession: AnyObject {
    var diagnostics: TranscriptionSessionDiagnostics { get }

    /// Prepares the session. Returns an audio chunk callback for streaming, or nil for file-based.
    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)?

    /// Called after recording stops. Returns the final transcribed text.
    /// `audioDurationSeconds` is computed once by the caller (from the same
    /// WAV read the pipeline needs for its own metrics) rather than having
    /// each conformer open the file again on the main-actor stop path.
    func transcribe(audioURL: URL, audioDurationSeconds: TimeInterval?) async throws -> String

    /// Cancel the session and clean up resources.
    func cancel()
}

// MARK: - File-Based Session

/// File-based session: records to file, uploads after stop.
@MainActor
final class FileTranscriptionSession: TranscriptionSession {
    private let service: TranscriptionService
    private var model: (any TranscriptionModel)?
    private(set) var diagnostics = TranscriptionSessionDiagnostics(sessionType: "batch")

    init(service: TranscriptionService) {
        self.service = service
    }

    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)? {
        self.model = model
        return nil
    }

    func transcribe(audioURL: URL, audioDurationSeconds: TimeInterval?) async throws -> String {
        guard let model = model else {
            throw SottoEngineError.transcriptionFailed
        }
        diagnostics = TranscriptionSessionDiagnostics(sessionType: "batch")
        return try await service.transcribe(audioURL: audioURL, model: model)
    }

    func cancel() {
        // No-op for file-based transcription
    }
}

// MARK: - Streaming Session

/// Streaming session with automatic fallback to file-based upload on failure.
@MainActor
final class StreamingTranscriptionSession: TranscriptionSession {
    private let streamingService: StreamingTranscriptionService
    private let fallbackService: TranscriptionService
    private var model: (any TranscriptionModel)?
    private var streamingFailed = false
    private var startTask: Task<Void, Never>?
    private(set) var diagnostics = TranscriptionSessionDiagnostics(sessionType: "streaming")
    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "StreamingTranscriptionSession")

    init(streamingService: StreamingTranscriptionService, fallbackService: TranscriptionService) {
        self.streamingService = streamingService
        self.fallbackService = fallbackService
    }

    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)? {
        self.model = model

        // Return callback immediately; WebSocket connects in background
        let service = streamingService
        let callback: (Data) -> Void = { [weak service] data in
            service?.sendAudioChunk(data)
        }

        let task = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                try await self.streamingService.startStreaming(model: model)
                await MainActor.run {
                    self.logger.notice("Streaming connected for \(model.displayName, privacy: .public)")
                }
            } catch {
                let desc = error.localizedDescription
                await MainActor.run {
                    self.logger.error("❌ Failed to start streaming, will fall back to batch: \(desc, privacy: .public)")
                    self.streamingFailed = true
                }
            }
        }
        startTask = task

        return callback
    }

    func transcribe(audioURL: URL, audioDurationSeconds durationSeconds: TimeInterval?) async throws -> String {
        guard let model = model else {
            throw SottoEngineError.transcriptionFailed
        }

        diagnostics = TranscriptionSessionDiagnostics(sessionType: "streaming")
        await startTask?.value
        startTask = nil

        if !streamingFailed {
            do {
                let text = try await streamingService.stopAndGetFinalText()
                diagnostics.streamingFinalLength = text.count
                logger.notice("Streaming transcript received")

                if let fallbackReason = Self.implausiblyShortFallbackReason(
                    text: text,
                    audioDurationSeconds: durationSeconds,
                    maxObservedTranscriptLength: streamingService.maxObservedTranscriptLength
                ) {
                    guard shouldUseBatchFallback(for: model) else {
                        // Parakeet Realtime EOU is streaming-only in Sotto. The
                        // empty/short-output fallback cannot batch-decode this
                        // same id, so return the streaming result instead of
                        // masking the selected recognizer with another model.
                        diagnostics.fallbackReason = "\(fallbackReason); batch fallback skipped for streaming-only model"
                        logger.warning("Streaming transcript implausibly short; batch fallback skipped for streaming-only model: \(fallbackReason, privacy: .public)")
                        return text
                    }

                    diagnostics.sessionType = "batch"
                    diagnostics.fallbackReason = fallbackReason
                    logger.warning("Streaming transcript implausibly short; falling back to batch: \(fallbackReason, privacy: .public)")

                    do {
                        return try await fallbackService.transcribe(audioURL: audioURL, model: model)
                    } catch {
                        logger.error("❌ Batch fallback failed after short streaming result; returning streaming text: \(error.localizedDescription, privacy: .public)")
                        diagnostics.sessionType = "streaming"
                        diagnostics.fallbackReason = "\(fallbackReason); batch fallback failed: \(error.localizedDescription)"
                        return text
                    }
                }

                return text
            } catch {
                diagnostics.fallbackReason = "streaming error: \(error.localizedDescription)"
                streamingService.cancel()
                guard shouldUseBatchFallback(for: model) else {
                    diagnostics.sessionType = "streaming"
                    logger.error("❌ Streaming failed; batch fallback skipped for streaming-only model: \(error.localizedDescription, privacy: .public)")
                    throw error
                }
                diagnostics.sessionType = "batch"
                logger.error("❌ Streaming failed, falling back to batch: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            diagnostics.fallbackReason = "streaming start failed"
            streamingService.cancel()
            guard shouldUseBatchFallback(for: model) else {
                diagnostics.sessionType = "streaming"
                throw SottoEngineError.transcriptionFailed
            }
            diagnostics.sessionType = "batch"
        }

        logger.notice("Using batch fallback for \(model.displayName, privacy: .public)")
        return try await fallbackService.transcribe(audioURL: audioURL, model: model)
    }

    func cancel() {
        startTask?.cancel()
        startTask = nil
        streamingService.cancel()
    }

    /// A dropped final commit shows up as a final result much shorter than what streaming
    /// already displayed — that comparison is independent of audio duration, which includes
    /// silence/pauses and isn't a reliable proxy for how much speech was actually said.
    nonisolated static func implausiblyShortFallbackReason(
        text: String,
        audioDurationSeconds: TimeInterval?,
        maxObservedTranscriptLength: Int
    ) -> String? {
        let nonWhitespaceCount = text.unicodeScalars.filter { !$0.properties.isWhitespace }.count
        if nonWhitespaceCount == 0 {
            return "empty streaming final"
        }

        guard maxObservedTranscriptLength > 0, nonWhitespaceCount * 2 < maxObservedTranscriptLength else {
            return nil
        }

        let durationDescription = audioDurationSeconds.map { String(format: "%.2fs audio", $0) } ?? "unknown duration"
        return "streaming final \(nonWhitespaceCount) chars vs max observed \(maxObservedTranscriptLength) chars for \(durationDescription)"
    }

    private func shouldUseBatchFallback(for model: any TranscriptionModel) -> Bool {
        !FluidAudioModelManager.isParakeetEouModel(named: model.name)
            && !FluidAudioModelManager.isNemotronStreamingModel(named: model.name)
    }
}
