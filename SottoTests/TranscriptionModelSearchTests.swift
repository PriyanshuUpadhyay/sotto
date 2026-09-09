import Testing
@testable import Sotto

struct TranscriptionModelSearchTests {
    private var models: [any TranscriptionModel] { TranscriptionModelMapper.availableModels() }

    @Test func hinglishSearchFindsWhisperOnly() {
        let results = TranscriptionModelSearch.results(in: models, query: "  HINGLISH  ")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.provider == .whisper })
    }

    @Test func regularListIncludesAppleSpeechAndRealtime() {
        let names = TranscriptionModelSearch.results(in: models, query: "").map(\.name)
        #expect(names.contains("apple-speech"))
        #expect(names.contains("parakeet-unified-0.6b"))
        #expect(!names.contains("cohere-transcribe-03-2026"))
        #expect(!names.contains("nemotron-streaming-en-0.6b"))
        #expect(!names.contains("parakeet-realtime-eou-120m"))
        #expect(!names.contains("parakeet-tdt-ctc-110m"))
    }

    @Test func unknownSearchHasNoResults() {
        #expect(TranscriptionModelSearch.results(in: models, query: "no-such-model").isEmpty)
    }

    @Test func whisperOffersThreeChoicesAndEnglishImportsStayEnglish() throws {
        let whisper = try #require(models.first { $0.name == "ggml-large-v3-turbo" })
        #expect(Set(whisper.supportedLanguages.keys) == ["en", "hinglish", "auto"])
        let imported = ImportedWhisperModel(fileBaseName: "ggml-base.en-q5_1")
        #expect(imported.supportedLanguages == ["en": "English"])
    }
}
