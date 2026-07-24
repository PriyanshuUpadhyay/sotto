import FluidAudio
import Foundation
import os

private final class EouCommitDeltaTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var lastCommittedTranscript = ""

    func reset() {
        lock.lock()
        lastCommittedTranscript = ""
        lock.unlock()
    }

    func nextCommittedSegment(from transcript: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return ""
        }

        lock.lock()

        guard !lastCommittedTranscript.isEmpty else {
            lastCommittedTranscript = trimmedTranscript
            lock.unlock()
            return TextNormalizer.shared.normalizeSentence(trimmedTranscript)
        }
        if trimmedTranscript == lastCommittedTranscript {
            lock.unlock()
            return ""
        }
        let segment: String
        if trimmedTranscript.hasPrefix(lastCommittedTranscript) {
            segment = trimmedTranscript
                .dropFirst(lastCommittedTranscript.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            segment = trimmedTranscript
        }
        lastCommittedTranscript = trimmedTranscript
        lock.unlock()

        return TextNormalizer.shared.normalizeSentence(segment)
    }

    func partialSegment(from transcript: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return ""
        }

        lock.lock()
        defer { lock.unlock() }

        guard !lastCommittedTranscript.isEmpty else {
            return trimmedTranscript
        }
        if trimmedTranscript == lastCommittedTranscript {
            return ""
        }
        if trimmedTranscript.hasPrefix(lastCommittedTranscript) {
            return trimmedTranscript
                .dropFirst(lastCommittedTranscript.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmedTranscript
    }
}

/// True streaming provider backed by FluidAudio's Parakeet Realtime EOU manager.
final class FluidAudioEouStreamingProvider: StreamingTranscriptionProvider {
    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "FluidAudioEouStreaming")
    private let cache: FluidAudioStreamingManagerCache
    private var manager: StreamingEouAsrManager?
    private var leaseId: UUID?
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private let commitDeltaTracker = EouCommitDeltaTracker()

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
        commitDeltaTracker.reset()

        let (manager, leaseId) = try await cache.acquireEou()
        let continuation = eventsContinuation
        let commitDeltaTracker = commitDeltaTracker
        await manager.setPartialCallback { partial in
            let segment = commitDeltaTracker.partialSegment(from: partial)
            guard !segment.isEmpty else { return }
            continuation?.yield(.partial(text: segment))
        }
        await manager.setEouCallback { transcript in
            let segment = commitDeltaTracker.nextCommittedSegment(from: transcript)
            guard !segment.isEmpty else { return }
            continuation?.yield(.committed(text: segment))
        }
        self.manager = manager
        self.leaseId = leaseId
        eventsContinuation?.yield(.sessionStarted)
        logger.notice("Parakeet Realtime EOU streaming started for \(model.displayName, privacy: .public)")
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
        let segment = commitDeltaTracker.nextCommittedSegment(from: finalText)
        // EOU callbacks emit cumulative finalized text during the session. At
        // finish(), FluidAudio returns the remaining accumulated transcript, so
        // only the unseen suffix is yielded to avoid double-appending prior EOUs.
        eventsContinuation?.yield(.committed(text: segment))
    }

    func disconnect() async {
        // Release the lease (if we hold one) instead of destroying the
        // manager — the cache retains and resets it for the next dictation.
        if let leaseId {
            await cache.release(family: .eou, leaseId: leaseId)
        }
        manager = nil
        leaseId = nil
        eventsContinuation?.finish()
        logger.notice("Parakeet Realtime EOU streaming disconnected")
    }
}
