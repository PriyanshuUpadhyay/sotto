import FluidAudio
import Foundation
import os

/// True streaming provider backed by FluidAudio's Parakeet Unified manager.
final class FluidAudioUnifiedStreamingProvider: StreamingTranscriptionProvider {
    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "FluidAudioUnifiedStreaming")
    private let cache: FluidAudioStreamingManagerCache
    private var manager: StreamingUnifiedAsrManager?
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
        let (manager, leaseId) = try await cache.acquireUnified()
        let continuation = eventsContinuation
        await manager.setPartialTranscriptCallback { partial in
            continuation?.yield(.partial(text: partial))
        }
        self.manager = manager
        self.leaseId = leaseId
        eventsContinuation?.yield(.sessionStarted)
        logger.notice("Parakeet Unified streaming started for \(model.displayName, privacy: .public)")
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let manager else {
            throw StreamingTranscriptionError.notConnected
        }

        guard let buffer = PCMAudioConverter.pcmBuffer(fromPCM16Data: data) else {
            return
        }

        try await manager.appendAudio(buffer)
        try await manager.processBufferedAudio()
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
            await cache.release(family: .unified, leaseId: leaseId)
        }
        manager = nil
        leaseId = nil
        eventsContinuation?.finish()
        logger.notice("Parakeet Unified streaming disconnected")
    }
}
