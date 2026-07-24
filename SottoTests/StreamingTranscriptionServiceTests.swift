import Testing
import Foundation
import SwiftData
@testable import Sotto

private final class FakeStreamingProvider: StreamingTranscriptionProvider {
    private let continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation
    let transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>
    var onCommit: (() -> Void)?

    init() {
        let (stream, continuation) = AsyncStream<StreamingTranscriptionEvent>.makeStream()
        self.transcriptionEvents = stream
        self.continuation = continuation
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {}
    func sendAudioChunk(_ data: Data) async throws {}

    func commit() async throws {
        onCommit?()
    }

    func disconnect() async {
        continuation.finish()
    }

    func emit(_ event: StreamingTranscriptionEvent) {
        continuation.yield(event)
    }
}

private final class TestableStreamingTranscriptionService: StreamingTranscriptionService {
    var nextProvider: FakeStreamingProvider! = nil

    override func createProvider(for model: any TranscriptionModel) -> StreamingTranscriptionProvider {
        nextProvider
    }
}

@Suite struct StreamingTranscriptionServiceTests {
    private func context() -> ModelContext {
        let schema = Schema([VocabularyWord.self])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try! ModelContainer(for: schema, configurations: [cfg]))
    }

    private let fakeModel = NativeAppleModel(
        name: "fake",
        displayName: "Fake",
        description: "",
        isMultilingualModel: false,
        supportedLanguages: [:]
    )

    @MainActor
    @Test("partial arriving while .committing still counts toward max-observed length; next session resets it")
    func partialDuringCommitUpdatesMaxObservedLength() async throws {
        let service = TestableStreamingTranscriptionService(modelContext: context())

        // A provider can still emit partials while queued audio drains after stop() flips
        // the state to .committing — that's exactly when this fake emits its longest
        // partial, right before the short final commit.
        let provider = FakeStreamingProvider()
        service.nextProvider = provider
        try await service.startStreaming(model: fakeModel)
        provider.onCommit = {
            provider.emit(.partial(text: "one two three four five six seven eight nine ten"))
            provider.emit(.committed(text: "one"))
        }

        let finalText = try await service.stopAndGetFinalText()
        #expect(finalText == "one")
        #expect(service.maxObservedTranscriptLength > finalText.count)
        #expect(service.maxObservedTranscriptLength >= 30)

        // A new session resets the counter before any of its own events arrive.
        let nextProvider = FakeStreamingProvider()
        service.nextProvider = nextProvider
        try await service.startStreaming(model: fakeModel)
        #expect(service.maxObservedTranscriptLength == 0)

        service.cancel()
    }
}
