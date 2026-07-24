import Foundation

/// Quality tiers the Models settings tab presents instead of raw model names.
/// Each tier maps to one concrete on-device model id present in the bundled
/// transcription manifest (see `TranscriptionModelMapper`). The mapping is
/// total — every case yields a non-empty, manager-known model name — so the
/// tier picker can always resolve a real model to hand to
/// `TranscriptionModelManager.setDefaultTranscriptionModel`.
enum TranscriptionTier: String, CaseIterable, Identifiable, Hashable {
    case fast
    case realtime
    case balanced
    case best
    case multilingual

    var id: String { rawValue }

    /// Reverse of `modelId`, derived by scanning `allCases` so it can never
    /// drift from the forward switch. Lets the picker reflect the current
    /// default model back as its tier; nil for ids no tier owns.
    init?(modelId: String) {
        guard let match = Self.allCases.first(where: { $0.modelId == modelId }) else {
            return nil
        }
        self = match
    }

    /// Concrete `TranscriptionModel.name` this tier selects. These are the
    /// in-app model names (whisper names derive from the manifest source_url
    /// basename, fluidaudio names are the manifest id).
    var modelId: String {
        switch self {
        case .fast:     return "parakeet-tdt-0.6b-v2"
        case .realtime: return "parakeet-unified-0.6b"
        case .balanced: return "ggml-large-v3-turbo-q5_0"
        case .best:     return "ggml-large-v3-turbo"
        case .multilingual: return "parakeet-tdt-0.6b-v3"
        }
    }

    var title: String {
        switch self {
        case .fast:     return "Fast"
        case .realtime: return "Realtime"
        case .balanced: return "Balanced"
        case .best:     return "Best"
        case .multilingual: return "Multilingual"
        }
    }

    var subtitle: String {
        switch self {
        case .fast:     return "On-device Parakeet V2 — fastest, English-only."
        case .realtime: return "Parakeet Unified — native streaming dictation, English-only."
        case .balanced: return "Quantized Whisper Turbo — multilingual, lighter."
        case .best:     return "Full Whisper Turbo — multilingual, highest quality."
        case .multilingual: return "Parakeet V3 — 25 languages, slightly lower English accuracy."
        }
    }
}
