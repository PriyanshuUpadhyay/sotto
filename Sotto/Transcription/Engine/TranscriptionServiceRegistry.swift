import Foundation
import SwiftUI
import SwiftData
import os

@MainActor
class TranscriptionServiceRegistry {
    private weak var modelProvider: (any WhisperModelProvider)?
    private let modelsDirectory: URL
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "TranscriptionServiceRegistry")

    private(set) lazy var localTranscriptionService = WhisperTranscriptionService(
        modelsDirectory: modelsDirectory,
        modelProvider: modelProvider
    )
    private lazy var unsupportedTranscriptionService = UnsupportedTranscriptionService()
    private(set) lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    private(set) lazy var fluidAudioTranscriptionService = FluidAudioTranscriptionService()
    private(set) lazy var fluidAudioStreamingManagerCache = FluidAudioStreamingManagerCache()

    init(modelProvider: any WhisperModelProvider, modelsDirectory: URL, modelContext: ModelContext) {
        self.modelProvider = modelProvider
        self.modelsDirectory = modelsDirectory
        self.modelContext = modelContext

        // Hand the FluidAudio service the container that owns VocabularyWord so
        // its file-based path can fetch the live custom vocabulary for
        // in-decoder rescoring. ModelContainer is Sendable; the service builds
        // its own ModelContext on its actor. Same instance serves the session
        // and registry transcribe paths.
        let container = modelContext.container
        let service = fluidAudioTranscriptionService
        Task { await service.setVocabularyContainer(container) }
    }

    func service(for provider: ModelProvider) -> TranscriptionService {
        switch provider {
        case .whisper:
            return localTranscriptionService
        case .fluidAudio:
            return fluidAudioTranscriptionService
        case .nativeApple:
            return nativeAppleTranscriptionService
        default:
            return unsupportedTranscriptionService
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let service = service(for: model.provider)
        logger.debug("Transcribing with \(model.displayName, privacy: .public) using \(String(describing: type(of: service)), privacy: .public)")
        return try await service.transcribe(audioURL: audioURL, model: model)
    }

    /// Creates a streaming or file-based session depending on the model's capabilities.
    func createSession(for model: any TranscriptionModel, onPartialTranscript: ((String) -> Void)? = nil) -> TranscriptionSession {
        if supportsStreaming(model: model) {
            let streamingService = StreamingTranscriptionService(
                modelContext: modelContext,
                fluidAudioService: model.provider == .fluidAudio ? fluidAudioTranscriptionService : nil,
                streamingManagerCache: model.provider == .fluidAudio ? fluidAudioStreamingManagerCache : nil,
                onPartialTranscript: onPartialTranscript
            )
            let fallback = service(for: model.provider)
            return StreamingTranscriptionSession(streamingService: streamingService, fallbackService: fallback)
        } else {
            return FileTranscriptionSession(service: service(for: model.provider))
        }
    }

    /// Whether the given model supports streaming transcription
    func supportsStreaming(model: any TranscriptionModel) -> Bool {
        guard model.supportsStreaming else { return false }
        if FluidAudioModelManager.isParakeetEouModel(named: model.name) {
            return true
        }
        if FluidAudioModelManager.isNemotronStreamingModel(named: model.name) {
            return true
        }
        return UserDefaults.standard.object(forKey: "streaming-enabled-\(model.name)") as? Bool ?? true
    }

    func cleanup() async {
        await fluidAudioTranscriptionService.cleanup()
        await fluidAudioStreamingManagerCache.cleanup()
    }
}

/// Fallback for `ModelProvider` cases with no on-device transcription service.
/// Cloud transcription was removed; no selectable model maps here, but the
/// exhaustive `service(for:)` switch still needs a value to return.
private struct UnsupportedTranscriptionService: TranscriptionService {
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        throw NSError(
            domain: "Sotto.Transcription",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "The model provider \(model.provider.rawValue) is not supported by this build."]
        )
    }
}
