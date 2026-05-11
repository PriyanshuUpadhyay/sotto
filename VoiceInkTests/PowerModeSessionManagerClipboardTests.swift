import Testing
import Foundation
import SwiftData
@testable import VoiceInk

@MainActor
final class StubPowerModeStateProvider: PowerModeStateProvider {
    var currentTranscriptionModel: (any TranscriptionModel)? { nil }
    var allAvailableModels: [any TranscriptionModel] { [] }
    var availableModels: [WhisperModelFile] { [] }
    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {}
    func cleanupModelResources() async {}
    func loadModel(_ model: WhisperModelFile) async throws {}
}

@MainActor
@Suite(.serialized)
struct PowerModeSessionManagerClipboardTests {

    private static let sessionKey = "powerModeActiveSession.v1"

    private func makeEnhancementService() -> AIEnhancementService {
        let schema = Schema([
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self,
            Snippet.self,
            ScratchpadDocument.self,
            ScratchpadVersion.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return AIEnhancementService(modelContext: container.mainContext)
    }

    private func loadPersistedSession() throws -> PowerModeSession? {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionKey) else { return nil }
        return try JSONDecoder().decode(PowerModeSession.self, from: data)
    }

    private func freshConfig(useClipboardContext: Bool) -> PowerModeConfig {
        PowerModeConfig(
            id: UUID(),
            name: "test",
            emoji: "🧪",
            enhanceLevel: .none,
            useScreenCapture: false,
            useClipboardContext: useClipboardContext
        )
    }

    @Test("PowerModeSessionManager captures useClipboardContext=true at session start and restores it on session end")
    func recordsAndRestoresWhenStartingTrue() async throws {
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)

        let service = makeEnhancementService()
        let provider = StubPowerModeStateProvider()
        let manager = PowerModeSessionManager.shared
        manager.configure(engine: provider, enhancementService: service)

        service.useClipboardContext = true

        await manager.beginSession(with: freshConfig(useClipboardContext: false))

        let persisted = try loadPersistedSession()
        #expect(persisted?.originalState.useClipboardContext == true)

        service.useClipboardContext = false

        await manager.endSession()

        #expect(service.useClipboardContext == true)

        UserDefaults.standard.removeObject(forKey: Self.sessionKey)
    }

    @Test("beginSession applies config.useClipboardContext=true to the service via applyConfiguration")
    func appliesConfigUseClipboardContextTrueOnBeginSession() async throws {
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)

        let service = makeEnhancementService()
        let provider = StubPowerModeStateProvider()
        let manager = PowerModeSessionManager.shared
        manager.configure(engine: provider, enhancementService: service)

        service.useClipboardContext = false

        await manager.beginSession(with: freshConfig(useClipboardContext: true))

        #expect(service.useClipboardContext == true)

        await manager.endSession()
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)
    }

    @Test("beginSession applies config.useClipboardContext=false to the service via applyConfiguration")
    func appliesConfigUseClipboardContextFalseOnBeginSession() async throws {
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)

        let service = makeEnhancementService()
        let provider = StubPowerModeStateProvider()
        let manager = PowerModeSessionManager.shared
        manager.configure(engine: provider, enhancementService: service)

        service.useClipboardContext = true

        await manager.beginSession(with: freshConfig(useClipboardContext: false))

        #expect(service.useClipboardContext == false)

        await manager.endSession()
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)
    }

    @Test("PowerModeSessionManager captures useClipboardContext=false at session start and restores it on session end")
    func recordsAndRestoresWhenStartingFalse() async throws {
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)

        let service = makeEnhancementService()
        let provider = StubPowerModeStateProvider()
        let manager = PowerModeSessionManager.shared
        manager.configure(engine: provider, enhancementService: service)

        service.useClipboardContext = false

        await manager.beginSession(with: freshConfig(useClipboardContext: true))

        let persisted = try loadPersistedSession()
        #expect(persisted?.originalState.useClipboardContext == false)

        service.useClipboardContext = true

        await manager.endSession()

        #expect(service.useClipboardContext == false)

        UserDefaults.standard.removeObject(forKey: Self.sessionKey)
    }
}
