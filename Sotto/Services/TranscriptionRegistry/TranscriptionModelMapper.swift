import Foundation

/// F07 adapter — maps `TranscriptionModelEntry` (Codable, F02) into the app's
/// `TranscriptionModel` representations at the registry → manager seam.
/// The loader stays pure-Codable; mapping concentrates here so a single place
/// owns "how a manifest row becomes an in-app model".
enum TranscriptionModelMapper {

    /// Map a single manifest entry to its concrete `TranscriptionModel` based
    /// on `entry.framework`. Unknown frameworks return nil and are skipped by
    /// callers; this keeps the manifest forward-compatible.
    static func map(_ entry: TranscriptionModelEntry) -> (any TranscriptionModel)? {
        switch entry.framework {
        case "apple_speech":
            return NativeAppleModel(
                name: entry.id,
                displayName: entry.display_name,
                description: entry.description,
                isMultilingualModel: entry.is_multilingual,
                supportedLanguages: LanguageDictionary.forProvider(
                    isMultilingual: entry.is_multilingual,
                    provider: .nativeApple
                )
            )
        case "fluidaudio_coreml":
            return FluidAudioModel(
                name: entry.id,
                displayName: entry.display_name,
                description: entry.description,
                size: formatSize(gb: entry.weights.size_gb),
                speed: deriveSpeed(rtfP50: entry.rtf_p50),
                accuracy: deriveAccuracy(wer: entry.wer),
                ramUsage: deriveRamGB(peakMB: entry.peak_ram_mb, fallback: 0.8),
                supportsStreaming: entry.supports_streaming,
                supportedLanguages: LanguageDictionary.forProvider(
                    isMultilingual: entry.is_multilingual,
                    provider: .fluidAudio
                )
            )
        case "whisper_cpp", "whisper_cpp_with_coreml_encoder":
            guard let name = whisperGgmlName(from: entry.weights.source_url) else {
                return nil
            }
            return WhisperModel(
                name: name,
                displayName: entry.display_name,
                size: formatSize(gb: entry.weights.size_gb),
                supportedLanguages: LanguageDictionary.forProvider(
                    isMultilingual: entry.is_multilingual,
                    provider: .whisper
                ),
                description: entry.description,
                speed: deriveSpeed(rtfP50: entry.rtf_p50),
                accuracy: deriveAccuracy(wer: entry.wer),
                ramUsage: deriveRamGB(peakMB: entry.peak_ram_mb, fallback: 1.8)
            )
        default:
            return nil
        }
    }

    /// Convenience: load + map all manifest entries into the app's on-device
    /// model list. Mirrors the shape of the deleted
    /// `TranscriptionModelRegistry.models` so callers keep reading a single
    /// "all known models" list.
    static func availableModels(
        using loader: TranscriptionRegistryLoader = TranscriptionRegistryLoader()
    ) -> [any TranscriptionModel] {
        return loader.entries().compactMap(map)
    }

    // MARK: - Helpers

    private static func formatSize(gb: Double) -> String {
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        return "\(Int(round(gb * 1000))) MB"
    }

    /// Best-effort accuracy proxy: 1 - mean(present WER values). Returns 0.9
    /// when the manifest exposes no WER data so UI dots stay populated.
    private static func deriveAccuracy(wer: [String: Double?]) -> Double {
        let values = wer.values.compactMap { $0 }
        guard !values.isEmpty else { return 0.9 }
        let mean = values.reduce(0, +) / Double(values.count)
        return max(0.0, min(1.0, 1.0 - mean))
    }

    /// Best-effort speed proxy from RTF (lower = faster). Picks the best
    /// available `rtf_p50` reading. Falls back to 0.75 when no data.
    private static func deriveSpeed(rtfP50: [String: Double?]) -> Double {
        let values = rtfP50.values.compactMap { $0 }.filter { $0 > 0 }
        guard let best = values.min() else { return 0.75 }
        return max(0.0, min(1.0, 1.0 - best))
    }

    private static func deriveRamGB(peakMB: Int?, fallback: Double) -> Double {
        guard let mb = peakMB else { return fallback }
        return Double(mb) / 1000.0
    }

    /// Derive the on-disk whisper basename from a manifest source_url.
    /// `.../ggml-large-v3-turbo.bin` → `ggml-large-v3-turbo`. WhisperModelManager
    /// matches downloaded files by this stem.
    private static func whisperGgmlName(from sourceURL: String) -> String? {
        guard let url = URL(string: sourceURL) else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? nil : stem
    }
}
