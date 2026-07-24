import FluidAudio
import Foundation
import os

/// True streaming provider backed by FluidAudio's Nemotron Speech Streaming manager.
final class FluidAudioNemotronStreamingProvider: StreamingTranscriptionProvider {
    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "FluidAudioNemotronStreaming")
    private let cache: FluidAudioStreamingManagerCache
    private var manager: StreamingNemotronAsrManager?
    private var leaseId: UUID?
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init(cache: FluidAudioStreamingManagerCache) {
        self.cache = cache
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        let (manager, leaseId) = try await cache.acquireNemotron()
        let continuation = eventsContinuation
        // Nemotron emits cumulative partial transcripts (no built-in EOU/commit
        // token); the streaming service treats prefixed partials as cumulative.
        await manager.setPartialCallback { partial in
            let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            continuation?.yield(.partial(text: trimmed))
        }
        self.manager = manager
        self.leaseId = leaseId
        eventsContinuation?.yield(.sessionStarted)
        logger.notice("Nemotron streaming started for \(model.displayName, privacy: .public)")
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let manager else {
            throw StreamingTranscriptionError.notConnected
        }

        guard let buffer = PCMAudioConverter.pcmBuffer(fromPCM16Data: data) else {
            return
        }

        _ = try await manager.process(audioBuffer: buffer)
    }

    func commit() async throws {
        guard let manager else {
            throw StreamingTranscriptionError.notConnected
        }

        let finalText = try await manager.finish()
        let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = TextNormalizer.shared.normalizeSentence(text)
        eventsContinuation?.yield(.committed(text: normalized))
    }

    func disconnect() async {
        // Release the lease (if we hold one) instead of destroying the
        // manager — the cache retains and resets it for the next dictation.
        if let leaseId {
            await cache.release(family: .nemotron, leaseId: leaseId)
        }
        manager = nil
        leaseId = nil
        eventsContinuation?.finish()
        logger.notice("Nemotron streaming disconnected")
    }
}
