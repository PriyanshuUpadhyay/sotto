import Foundation

// MARK: - RecorderStateProvider

extension SottoEngine: RecorderStateProvider {
    /// Pretty `"PROVIDER · MODEL"` label for the active transcription model
    /// (e.g. `"WHISPER · LARGE-V3"`). Surfaced in `ChipPanel` via
    /// `ClusterChips.transcribingChips` during the `.transcribing` phase.
    /// Returns nil when no model is selected — the orchestrator falls back
    /// to a default chip label.
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
