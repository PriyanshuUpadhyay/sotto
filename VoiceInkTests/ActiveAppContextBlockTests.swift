import Testing
import Foundation
import SwiftData
@testable import Sotto

@MainActor
@Suite(.serialized)
struct ActiveAppContextBlockTests {

    private static let key = "useActiveAppContext"

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self,
            Snippet.self,
            ScratchpadDocument.self,
            ScratchpadVersion.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    @Test("ACTIVE_APP block present when useActiveAppContext default (unset → true)")
    func blockPresentWhenDefaultUnset() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { (name: "TestApp", bundleID: "com.example.test") }

        let prompt = await service.getSystemMessage(for: .transcriptionEnhancement)

        #expect(prompt.contains("<ACTIVE_APP>"))
        #expect(prompt.contains("</ACTIVE_APP>"))
        #expect(prompt.contains("name=TestApp"))
        #expect(prompt.contains("bundle=com.example.test"))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("ACTIVE_APP block present when useActiveAppContext explicitly true")
    func blockPresentWhenExplicitlyTrue() async {
        UserDefaults.standard.set(true, forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { (name: "Safari", bundleID: "com.apple.Safari") }

        let prompt = await service.getSystemMessage(for: .transcriptionEnhancement)

        #expect(prompt.contains("<ACTIVE_APP>\nname=Safari\nbundle=com.apple.Safari\n</ACTIVE_APP>"))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("ACTIVE_APP block omitted when useActiveAppContext is false")
    func blockOmittedWhenFalse() async {
        UserDefaults.standard.set(false, forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { (name: "Hidden", bundleID: "com.example.hidden") }

        let prompt = await service.getSystemMessage(for: .transcriptionEnhancement)

        #expect(!prompt.contains("<ACTIVE_APP>"))
        #expect(!prompt.contains("</ACTIVE_APP>"))
        #expect(!prompt.contains("com.example.hidden"))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("ACTIVE_APP block omitted when frontmostAppProvider returns nil")
    func blockOmittedWhenProviderReturnsNil() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { nil }

        let prompt = await service.getSystemMessage(for: .transcriptionEnhancement)

        #expect(!prompt.contains("<ACTIVE_APP>"))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("ACTIVE_APP block sits alongside CLIPBOARD_CONTEXT (same wrapping style)")
    func blockAlongsideClipboardContext() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.useClipboardContext = true
        service.lastCapturedClipboard = "clipboard payload"
        service.frontmostAppProvider = { (name: "Xcode", bundleID: "com.apple.dt.Xcode") }

        let prompt = await service.getSystemMessage(for: .transcriptionEnhancement)

        #expect(prompt.contains("<CLIPBOARD_CONTEXT>\nclipboard payload\n</CLIPBOARD_CONTEXT>"))
        #expect(prompt.contains("<ACTIVE_APP>\nname=Xcode\nbundle=com.apple.dt.Xcode\n</ACTIVE_APP>"))

        service.useClipboardContext = false
        service.lastCapturedClipboard = nil
        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
