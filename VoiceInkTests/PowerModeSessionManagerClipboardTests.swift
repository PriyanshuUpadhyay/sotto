import Testing
import Foundation
@testable import VoiceInk

struct PowerModeSessionManagerClipboardTests {

    @Test("session start records useClipboardContext and session end restores it (true)")
    func recordAndRestoreClipboardContextTrue() throws {
        let recorded = ApplicationState(
            enhanceLevel: .medium,
            useScreenCaptureContext: false,
            useClipboardContext: true,
            selectedPromptId: nil,
            selectedAIProvider: nil,
            selectedAIModel: nil,
            selectedLanguage: nil,
            transcriptionModelName: nil
        )

        #expect(recorded.useClipboardContext == true)

        let data = try JSONEncoder().encode(recorded)
        let restored = try JSONDecoder().decode(ApplicationState.self, from: data)

        #expect(restored.useClipboardContext == true)
    }

    @Test("session start records useClipboardContext and session end restores it (false)")
    func recordAndRestoreClipboardContextFalse() throws {
        let recorded = ApplicationState(
            enhanceLevel: .none,
            useScreenCaptureContext: true,
            useClipboardContext: false,
            selectedPromptId: nil,
            selectedAIProvider: nil,
            selectedAIModel: nil,
            selectedLanguage: nil,
            transcriptionModelName: nil
        )

        #expect(recorded.useClipboardContext == false)

        let data = try JSONEncoder().encode(recorded)
        let restored = try JSONDecoder().decode(ApplicationState.self, from: data)

        #expect(restored.useClipboardContext == false)
    }
}
