import Foundation

// MARK: - RecorderStateProvider

extension VoiceInkEngine: RecorderStateProvider {
    /// Pretty `"PROVIDER · MODEL"` label for the active transcription model
    /// (e.g. `"WHISPER · LARGE-V3"`). Surfaced in ConstellationCard's
    /// `.transcribing` row. Returns nil when no model is selected — the
    /// orchestrator falls back to the card's default placeholder.
    var transcriptionModelLabel: String? {
        guard let model = transcriptionModelManager.currentTranscriptionModel else {
            return nil
        }
        let provider = model.provider.rawValue.uppercased()
        let display = model.displayName
            .uppercased()
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: " ", with: "-")
        return display.isEmpty ? provider : "\(provider) · \(display)"
    }
}

// MARK: - PowerModeStateProvider

extension VoiceInkEngine: PowerModeStateProvider {
    var currentTranscriptionModel: (any TranscriptionModel)? {
        transcriptionModelManager.currentTranscriptionModel
    }

    var allAvailableModels: [any TranscriptionModel] {
        transcriptionModelManager.allAvailableModels
    }

    var availableModels: [WhisperModelFile] {
        whisperModelManager.availableModels
    }

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        transcriptionModelManager.setDefaultTranscriptionModel(model)
    }

    func cleanupModelResources() async {
        await cleanupResources()
    }

    func loadModel(_ model: WhisperModelFile) async throws {
        try await whisperModelManager.loadModel(model)
    }
}
