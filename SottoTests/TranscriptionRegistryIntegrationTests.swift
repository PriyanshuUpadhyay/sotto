import Testing
import Foundation
@testable import Sotto

// Manifest → mapper integration. Proves: the bundled manifest's entries map
// through TranscriptionModelMapper without silent drops, the default entry is
// reachable for fresh installs, and the imported-whisper side-load path still
// routes through the manager unchanged.
struct TranscriptionRegistryIntegrationTests {

    @Test func allModelsSourcedFromManifestViaMapper() throws {
        let loader = TranscriptionRegistryLoader()
        let allModels = TranscriptionModelMapper.availableModels(using: loader)
        #expect(allModels.contains(where: { $0.name == "parakeet-tdt-0.6b-v2" }),
                "default manifest entry must surface through the mapper")
        #expect(allModels.contains(where: { $0.name == "ggml-large-v3-turbo" }),
                "whisper turbo manifest entry must surface through the mapper")
    }

    @Test func defaultManifestEntryReachableForUnsetUserDefaults() throws {
        let loader = TranscriptionRegistryLoader()
        let defaultEntry = loader.entries().first(where: { $0.is_default })
        let mapped = TranscriptionModelMapper.availableModels(using: loader)
        #expect(defaultEntry != nil, "bundled manifest must declare a default entry")
        if let defaultEntry {
            #expect(mapped.contains(where: { $0.name == defaultEntry.id }),
                    "mapper must surface the manifest's is_default entry under its manifest id")
        }
    }

    @Test func loaderIsSourceOfTruth() throws {
        let loader = TranscriptionRegistryLoader()
        let manifestEntries = loader.entries()
        let mapped = manifestEntries.compactMap(TranscriptionModelMapper.map)
        #expect(manifestEntries.count == 11,
                "v1 manifest non-cloud entries (nemotron-streaming-en-0.6b + parakeet-tdt-ctc-110m + cohere-transcribe-03-2026 added as experimental)")
        #expect(manifestEntries.contains(where: { $0.id == "parakeet-unified-0.6b" }),
                "manifest must include the Parakeet Unified entry")
        #expect(mapped.count == manifestEntries.count,
                "every manifest entry's framework must be handled by the mapper (no silent drops)")
    }

    // Closing local-only verification (f10): every model the manifest → mapper
    // surface exposes must belong to the on-device provider set. ModelProvider
    // ships only {.whisper, .fluidAudio, .nativeApple}, so this passes
    // green-by-construction today; it RED-trips the instant a cloud/remote
    // framework regresses back into the manifest or mapper.
    @Test func everyMappedModelIsOnDeviceProvider() throws {
        let loader = TranscriptionRegistryLoader()
        let onDevice: Set<ModelProvider> = [.whisper, .fluidAudio, .nativeApple]
        for model in TranscriptionModelMapper.availableModels(using: loader) {
            #expect(onDevice.contains(model.provider),
                    "model \(model.name) surfaced via a non-on-device provider \(model.provider) — transcription surface must stay local-only")
        }
    }

    @Test func importedWhisperModelFlowUnchanged() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let worktreeRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let managerURL = worktreeRoot
            .appendingPathComponent("Sotto/Transcription/Engine/TranscriptionModelManager.swift")
        let src = try String(contentsOf: managerURL, encoding: .utf8)

        #expect(src.contains("whisperModelManager?.availableModels"),
                "manager must still iterate WhisperModelManager.availableModels for side-loaded models")
        #expect(src.contains("ImportedWhisperModel(fileBaseName:"),
                "manager must still wrap side-loaded entries as ImportedWhisperModel")
    }
}
