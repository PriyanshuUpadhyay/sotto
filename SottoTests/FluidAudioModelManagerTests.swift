import FluidAudio
import SwiftData
import Testing
@testable import Sotto

@Suite struct FluidAudioModelManagerTests {

    @Test("known TDT ids map to their expected ASR versions")
    func knownTDTIdsMapToVersions() {
        #expect(FluidAudioModelManager.knownAsrVersion(for: "parakeet-tdt-0.6b-v2") == .v2)
        #expect(FluidAudioModelManager.knownAsrVersion(for: "parakeet-tdt-0.6b-v3") == .v3)
        #expect(FluidAudioModelManager.knownAsrVersion(for: "parakeet-tdt-ctc-110m") == .tdtCtc110m)
    }

    @Test("Nemotron streaming id is recognized separately and not a batch TDT id")
    func nemotronStreamingModelRecognition() {
        #expect(FluidAudioModelManager.isNemotronStreamingModel(named: "nemotron-streaming-en-0.6b"))
        #expect(!FluidAudioModelManager.isNemotronStreamingModel(named: "parakeet-tdt-ctc-110m"))
        #expect(FluidAudioModelManager.knownAsrVersion(for: "nemotron-streaming-en-0.6b") == nil)
    }

    @Test("Nemotron streaming cache directory mirrors FluidAudio repo folder")
    func nemotronStreamingCacheDirectoryShape() {
        let path = FluidAudioModelManager.nemotronStreamingCacheDirectory().path
        #expect(path.hasSuffix("/FluidAudio/Models/nemotron-streaming/560ms"))
    }

    @Test("unknown FluidAudio ids are reported as unknown")
    func unknownIdsDoNotDefaultToV3() {
        #expect(FluidAudioModelManager.knownAsrVersion(for: "parakeet-realtime-eou-120m") == nil)
        #expect(FluidAudioModelManager.knownAsrVersion(for: "not-a-fluid-audio-model") == nil)
    }

    @Test("Parakeet EOU id is recognized separately from TDT ids")
    func parakeetEouModelRecognition() {
        #expect(FluidAudioModelManager.isParakeetEouModel(named: "parakeet-realtime-eou-120m"))
        #expect(!FluidAudioModelManager.isParakeetEouModel(named: "parakeet-tdt-0.6b-v3"))
        #expect(!FluidAudioModelManager.isParakeetEouModel(named: "not-a-fluid-audio-model"))
    }

    @Test("Parakeet EOU cache directory mirrors FluidAudio repo folder")
    func parakeetEouCacheDirectoryShape() {
        let path = FluidAudioModelManager.parakeetEouCacheDirectory().path
        #expect(path.hasSuffix("/FluidAudio/Models/parakeet-eou-streaming/160ms"))
    }

    @MainActor
    @Test("EOU streaming model resolves to the EOU provider")
    func eouStreamingModelCreatesEouProvider() throws {
        let schema = Schema([VocabularyWord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        let service = StreamingTranscriptionService(modelContext: context, streamingManagerCache: FluidAudioStreamingManagerCache())
        let model = FluidAudioModel(
            name: "parakeet-realtime-eou-120m",
            displayName: "Parakeet Realtime (EOU)",
            description: "Streaming EOU test model",
            size: "250 MB",
            speed: 1,
            accuracy: 1,
            ramUsage: 400,
            supportsStreaming: true,
            supportedLanguages: ["en": "English"]
        )

        #expect(service.createProvider(for: model) is FluidAudioEouStreamingProvider)
    }

    @MainActor
    @Test("Nemotron streaming model resolves to the Nemotron provider")
    func nemotronStreamingModelCreatesNemotronProvider() throws {
        let schema = Schema([VocabularyWord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        let service = StreamingTranscriptionService(modelContext: context, streamingManagerCache: FluidAudioStreamingManagerCache())
        let model = FluidAudioModel(
            name: "nemotron-streaming-en-0.6b",
            displayName: "Nemotron Speech Streaming",
            description: "Streaming Nemotron test model",
            size: "600 MB",
            speed: 1,
            accuracy: 1,
            ramUsage: 800,
            supportsStreaming: true,
            supportedLanguages: ["en": "English"]
        )

        #expect(service.createProvider(for: model) is FluidAudioNemotronStreamingProvider)
    }
}
