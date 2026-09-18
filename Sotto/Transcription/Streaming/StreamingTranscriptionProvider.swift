import Foundation

/// Events emitted by a streaming transcription provider
enum StreamingTranscriptionEvent {
    case sessionStarted
    case partial(text: String)
    case committed(text: String)
    case error(Error)
}

/// Errors specific to streaming transcription
enum StreamingTranscriptionError: LocalizedError {
    case missingAPIKey
    case connectionFailed(String)
    case timeout
    case serverError(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key not configured for streaming transcription"
        case .connectionFailed(let message):
            return "Streaming connection failed: \(message)"
        case .timeout:
            return "Streaming transcription timed out waiting for final result"
        case .serverError(let message):
            return "Streaming server error: \(message)"
        case .notConnected:
            return "Not connected to streaming transcription service"
        }
    }
}

/// Protocol for streaming transcription providers.
protocol StreamingTranscriptionProvider: AnyObject {
    /// Connect to the streaming transcription endpoint
    func connect(model: any TranscriptionModel, language: String?) async throws

    /// Send a chunk of raw PCM audio data (16-bit, 16kHz, mono, little-endian)
    func sendAudioChunk(_ data: Data) async throws

    /// Commit the current audio buffer to finalize transcription
    func commit() async throws

    /// Disconnect from the streaming endpoint
    func disconnect() async

    /// Stream of transcription events from the provider
    var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent> { get }

    /// Per-word confidence for the confirmed transcript, when the provider's
    /// decoder reports it. Read after `commit()`.
    ///
    /// Not part of `StreamingTranscriptionEvent`: the events carry plain text to
    /// the live UI, and only the pipeline's post-run trace wants the scores, so
    /// widening every event case (and every provider that emits one) would buy
    /// nothing. Defaults to empty, which is the honest answer for the cloud and
    /// Unified providers — they expose no per-token scores.
    var confirmedWordConfidences: [TimedWord] { get }
}

extension StreamingTranscriptionProvider {
    var confirmedWordConfidences: [TimedWord] { [] }
}
