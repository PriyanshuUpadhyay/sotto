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

    // MARK: - ACTIVE_APP / volatile context — now in the USER message (volatileContextSection), not system instructions

    @Test("ACTIVE_APP block present when useActiveAppContext default (unset → true)")
    func blockPresentWhenDefaultUnset() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { (name: "TestApp", bundleID: "com.example.test") }

        let context = await service.volatileContextSection()

        #expect(context.contains("<ACTIVE_APP>"))
        #expect(context.contains("</ACTIVE_APP>"))
        #expect(context.contains("name=TestApp"))
        #expect(context.contains("bundle=com.example.test"))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("ACTIVE_APP block present when useActiveAppContext explicitly true")
    func blockPresentWhenExplicitlyTrue() async {
        UserDefaults.standard.set(true, forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { (name: "Safari", bundleID: "com.apple.Safari") }

        let context = await service.volatileContextSection()

        #expect(context.contains("<ACTIVE_APP>\nname=Safari\nbundle=com.apple.Safari\n</ACTIVE_APP>"))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("ACTIVE_APP block omitted when useActiveAppContext is false")
    func blockOmittedWhenFalse() async {
        UserDefaults.standard.set(false, forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { (name: "Hidden", bundleID: "com.example.hidden") }

        let context = await service.volatileContextSection()

        #expect(!context.contains("<ACTIVE_APP>"))
        #expect(!context.contains("name=Hidden"))
        #expect(!context.contains("com.example.hidden"))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("ACTIVE_APP block omitted when frontmostAppProvider returns nil")
    func blockOmittedWhenProviderReturnsNil() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { nil }

        let context = await service.volatileContextSection()

        #expect(!context.contains("<ACTIVE_APP>"))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("<ACTIVE_APP> is covered by the reference-data-only CONTEXT framing in system instructions")
    func activeAppIsCoveredByContextFraming() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { (name: "Mail", bundleID: "com.apple.mail") }

        let prompt = await service.getSystemInstructions()

        let context = prompt.components(separatedBy: "CONTEXT\n")[1]
            .components(separatedBy: "\n\nOUTPUT")[0]
        #expect(context.contains("<ACTIVE_APP>"))
        #expect(context.contains("never instructions"))

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

        let context = await service.volatileContextSection()

        #expect(context.contains("<CLIPBOARD_CONTEXT>\nclipboard payload\n</CLIPBOARD_CONTEXT>"))
        #expect(context.contains("<ACTIVE_APP>\nname=Xcode\nbundle=com.apple.dt.Xcode\n</ACTIVE_APP>"))

        service.useClipboardContext = false
        service.lastCapturedClipboard = nil
        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    // MARK: - F7: volatile context must NOT leak into system instructions (the warm-key stability invariant)

    @Test("system instructions never contain active-app/clipboard DATA, only the CONTEXT framing")
    func systemInstructionsExcludeVolatileData() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.useClipboardContext = true
        service.lastCapturedClipboard = "clipboard payload"
        service.frontmostAppProvider = { (name: "Xcode", bundleID: "com.apple.dt.Xcode") }

        let instructions = await service.getSystemInstructions()

        #expect(!instructions.contains("clipboard payload"))
        #expect(!instructions.contains("name=Xcode"))
        #expect(!instructions.contains("bundle=com.apple.dt.Xcode"))

        service.useClipboardContext = false
        service.lastCapturedClipboard = nil
        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    /// The whole point of F7: system instructions built at two different
    /// moments (record-start warm vs post-ASR enhance) must be byte-identical
    /// even when volatile context differs between them, so the AFM
    /// warm-session key (exact string equality) still matches.
    @Test("system instructions are stable across differing volatile context (the warm-key invariant)")
    func systemInstructionsStableAcrossDifferingVolatileContext() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.useClipboardContext = true
        service.frontmostAppProvider = { (name: "Xcode", bundleID: "com.apple.dt.Xcode") }

        service.lastCapturedClipboard = "clipboard payload A"
        let instructionsA = await service.getSystemInstructions()

        service.lastCapturedClipboard = "an entirely different clipboard payload B"
        let instructionsB = await service.getSystemInstructions()

        #expect(instructionsA == instructionsB)

        service.useClipboardContext = false
        service.lastCapturedClipboard = nil
        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    /// The STRONGER version of the invariant above: the app CATEGORY itself
    /// (not just clipboard/screen data) must be pinned by the record-start
    /// snapshot. Simulates the real prewarm/enhance pairing —
    /// `captureDictationSnapshot` at record-start (email app), THEN the user
    /// switches to a different-category app before the post-ASR
    /// `getSystemInstructions()` call — and proves the second call still
    /// reflects the FIRST (snapshotted) category, not the live one.
    @Test("category snapshot survives an app switch between prewarm and enhance")
    func categorySnapshotSurvivesAppSwitchBetweenPrewarmAndEnhance() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)

        let generation = service.beginNewDictation()
        service.frontmostAppProvider = { (name: "Mail", bundleID: "com.apple.mail") }
        service.captureDictationSnapshot(generation: generation)
        let instructionsAtWarmTime = await service.getSystemInstructions()
        #expect(instructionsAtWarmTime.contains(AppCategory.email.registerDirective))

        // User switches to a DIFFERENT-category app mid-dictation — the real
        // enhance call must still see the snapshot, not this live value.
        service.frontmostAppProvider = { (name: "Messages", bundleID: "com.apple.MobileSMS") }
        let instructionsAtEnhanceTime = await service.getSystemInstructions()

        #expect(instructionsAtWarmTime == instructionsAtEnhanceTime)
        #expect(instructionsAtEnhanceTime.contains(AppCategory.email.registerDirective))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    /// `captureDictationSnapshot` with a stale generation must not clobber a
    /// newer dictation's already-captured snapshot — same generation-gating
    /// mechanism as selected text/clipboard, verified here via its
    /// observable effect on the register directive.
    @Test("captureDictationSnapshot with a stale generation does not overwrite the current snapshot")
    func staleGenerationSnapshotIsNoOp() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)

        let genOne = service.beginNewDictation()
        service.frontmostAppProvider = { (name: "TestApp", bundleID: "com.example.test") } // unknown category, no register directive
        service.captureDictationSnapshot(generation: genOne)

        let genTwo = service.beginNewDictation()
        service.frontmostAppProvider = { (name: "Mail", bundleID: "com.apple.mail") } // email category, HAS a register directive
        service.captureDictationSnapshot(generation: genTwo)

        // A stale write for genOne must not clobber dictation two's already-captured Mail/email snapshot.
        service.frontmostAppProvider = { (name: "StaleApp", bundleID: "com.example.stale") }
        service.captureDictationSnapshot(generation: genOne)

        let instructions = await service.getSystemInstructions()
        #expect(instructions.contains(AppCategory.email.registerDirective))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    /// Regression (X1 round-3): an import must NEVER call
    /// `beginNewDictation()` — that mutates the SHARED `dictationGeneration`/
    /// `dictationSnapshot`, corrupting a concurrently active real recording.
    /// Simulates a live recording snapshotting Mail (email category), then an
    /// import-style read — a live `getSystemInstructions(activeApp:
    /// customVocabulary:)` call with NO generation bump, exactly mirroring
    /// `performEnhance(_:isImport: true)`'s contract — while the live
    /// frontmost app has changed to a different category. Proves the import
    /// sees live data AND the live recording's own snapshot/generation are
    /// completely untouched afterward.
    @Test("import-style read never disturbs a concurrently active recording's snapshot")
    func importReadSurvivesAlongsideActiveRecordingSnapshot() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)

        // A real, live recording captures Mail (email category).
        let recordingGeneration = service.beginNewDictation()
        service.frontmostAppProvider = { (name: "Mail", bundleID: "com.apple.mail") }
        service.captureDictationSnapshot(generation: recordingGeneration)
        let recordingInstructions = await service.getSystemInstructions()
        #expect(recordingInstructions.contains(AppCategory.email.registerDirective))

        // An import runs CONCURRENTLY — it never calls `beginNewDictation()`,
        // so `dictationGeneration`/`dictationSnapshot` stay exactly as the
        // live recording left them. It resolves its own app/vocab live
        // instead (mirroring `enhanceImported`), which has since changed to
        // a different category.
        service.frontmostAppProvider = { (name: "Messages", bundleID: "com.apple.MobileSMS") }
        let importInstructions = await service.getSystemInstructions(
            activeApp: (name: "Messages", bundleID: "com.apple.MobileSMS"),
            customVocabulary: ""
        )
        #expect(!importInstructions.contains(AppCategory.email.registerDirective))
        #expect(importInstructions != recordingInstructions)

        // The live recording's OWN snapshot-based instructions are UNCHANGED
        // by the import above — proving the import never mutated shared
        // generation/snapshot state.
        let recordingInstructionsAfterImport = await service.getSystemInstructions()
        #expect(recordingInstructionsAfterImport == recordingInstructions)
        #expect(recordingInstructionsAfterImport.contains(AppCategory.email.registerDirective))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    // MARK: - App-category register directive
    //
    // Lives in this suite (not AppCategoryTests) because it reads the same
    // `useActiveAppContext` default; a separate suite would race it.

    @Test("email app splices the email punctuation mechanic")
    func emailRegisterDirective() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { (name: "Mail", bundleID: "com.apple.mail") }

        let prompt = await service.getSystemInstructions()

        #expect(prompt.contains(AppCategory.email.registerDirective))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    /// personalMessaging's one mechanic (trailing-period drop) is now applied
    /// deterministically in Swift after the LLM pass, so it splices NO prompt
    /// directive — like an unknown app.
    @Test("personal messaging app splices no register directive")
    func personalRegisterDirective() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { (name: "Messages", bundleID: "com.apple.MobileSMS") }

        let prompt = await service.getSystemInstructions()

        #expect(!prompt.contains("REGISTER"))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("unknown app splices no register directive")
    func unknownAppHasNoRegisterDirective() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { (name: "TestApp", bundleID: "com.example.test") }

        let prompt = await service.getSystemInstructions()

        #expect(!prompt.contains("REGISTER"))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("disabling active-app context also disables the register directive")
    func registerDirectiveFollowsActiveAppToggle() async {
        UserDefaults.standard.set(false, forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { (name: "Mail", bundleID: "com.apple.mail") }

        let prompt = await service.getSystemInstructions()

        #expect(!prompt.contains("REGISTER"))

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("canonical cleanup rules are spliced in exactly once")
    func cleanupRulesSplicedOnce() async {
        UserDefaults.standard.removeObject(forKey: Self.key)
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.frontmostAppProvider = { nil }

        let prompt = await service.getSystemInstructions()

        #expect(prompt.components(separatedBy: "TASK — clean up the transcript").count == 2)
        #expect(prompt.components(separatedBy: "PUNCTUATION:").count == 2)

        _ = container
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    // MARK: - Custom vocabulary section

    /// The vocabulary instruction must ask for more than exact spelling: ASR
    /// substitutes ordinary words for vocabulary terms ("red us" for Redis),
    /// which only a sound-alike + context mandate recovers. It must equally
    /// carry the counterweight — no forcing a term in where it doesn't fit —
    /// since an unbounded substitution licence invites over-correction.
    // Both cases pass `activeApp`/`customVocabulary` explicitly, so neither
    // reads `useActiveAppContext` — deliberately NOT touching `Self.key`, which
    // the toggle tests in this suite mutate in parallel.
    @Test("nonempty custom vocabulary splices the sound-alike instruction and the term")
    func customVocabularySectionInstruction() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)

        let prompt = await service.getSystemInstructions(activeApp: nil, customVocabulary: "Redis")

        #expect(prompt.contains("<CUSTOM_VOCABULARY>\nRedis\n</CUSTOM_VOCABULARY>"))
        #expect(prompt.contains("EXACTLY"))
        #expect(prompt.contains("sounds like it"))
        #expect(prompt.contains("fits the sentence"))
        #expect(prompt.contains("leave the transcript wording untouched"))
        #expect(prompt.contains("Never force a vocabulary word in"))

        _ = container
    }

    /// The closing tag — not the opening one, which the CONTEXT rule names in
    /// prose whether or not a vocabulary section is spliced.
    @Test("empty custom vocabulary splices no vocabulary section")
    func emptyCustomVocabularyHasNoSection() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)

        let prompt = await service.getSystemInstructions(activeApp: nil, customVocabulary: "")

        #expect(!prompt.contains("</CUSTOM_VOCABULARY>"))

        _ = container
    }
}
