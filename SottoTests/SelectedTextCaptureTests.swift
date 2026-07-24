import Testing
import Foundation
import SwiftData
@testable import Sotto

/// X1/F6: selected text is captured ONCE at record-start (detached) and the
/// post-ASR path awaits the cached result instead of fetching live. These
/// tests drive `selectedTextProvider` (a fake, no real AX/menu-Copy access)
/// to verify the capture-then-await-with-grace mechanics, and the dictation-
/// generation gating that scopes every capture to the dictation that issued
/// it, without depending on real accessibility state.
@MainActor
struct SelectedTextCaptureTests {

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

    @Test("captured selected text appears in the volatile context section")
    func capturedSelectedTextAppearsInContext() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.selectedTextProvider = { "some selected text" }

        let generation = service.beginNewDictation()
        service.captureSelectedTextContext(generation: generation)
        let context = await service.volatileContextSection()

        #expect(context.contains("<CURRENTLY_SELECTED_TEXT>\nsome selected text\n</CURRENTLY_SELECTED_TEXT>"))
        _ = container
    }

    @Test("no capture in flight means no selected-text block")
    func noCaptureMeansNoBlock() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)

        let context = await service.volatileContextSection()

        #expect(!context.contains("CURRENTLY_SELECTED_TEXT"))
        _ = container
    }

    @Test("nil from the provider (no selection / AX unavailable) means no selected-text block")
    func nilProviderMeansNoBlock() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.selectedTextProvider = { nil }

        let generation = service.beginNewDictation()
        service.captureSelectedTextContext(generation: generation)
        let context = await service.volatileContextSection()

        #expect(!context.contains("CURRENTLY_SELECTED_TEXT"))
        _ = container
    }

    /// The grace period (300ms) must cut off a stuck fetch rather than stall
    /// enhancement indefinitely — proceeding without selected-text context,
    /// same as AX being unavailable. This is what a `withTaskGroup`/`cancelAll`
    /// race gets WRONG (a group waits for every child, including one that
    /// isn't cooperatively cancellable, so a stuck fetch hangs the whole
    /// group) — the continuation-based `SelectedTextSlot` doesn't have that
    /// problem, and this test is what proves it.
    @Test("a slow fetch past the grace period yields no block, not a hang")
    func slowFetchTimesOutGracefully() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.selectedTextProvider = {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s — well past the 300ms grace
            return "too slow to matter"
        }

        let generation = service.beginNewDictation()
        service.captureSelectedTextContext(generation: generation)
        let clock = ContinuousClock()
        let start = clock.now
        let context = await service.volatileContextSection()
        let elapsed = clock.now - start

        #expect(!context.contains("CURRENTLY_SELECTED_TEXT"))
        #expect(elapsed < .milliseconds(800), "expected the grace timeout (~300ms) to cut this off, took \(elapsed)")
        _ = container
    }

    /// A fetch that finishes WELL within the grace period must not be held
    /// up waiting out the full grace window — the race returns as soon as
    /// the fetch task completes.
    @Test("fast fetch delivers the captured value rather than timing out")
    func fastFetchDeliversValueWithinGrace() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.selectedTextProvider = { "instant" }

        let generation = service.beginNewDictation()
        service.captureSelectedTextContext(generation: generation)
        let context = await service.volatileContextSection()

        // Receiving the VALUE proves the write-signal won the race: a grace
        // timeout resumes nil, never the value, so no wall-clock assertion is
        // needed (and any would flake under parallel-test main-actor load).
        #expect(context.contains("instant"))
        _ = container
    }

    @Test("clearCapturedContexts drops the in-flight capture slot")
    func clearCapturedContextsDropsCapture() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.selectedTextProvider = { "leftover from a previous dictation" }

        let generation = service.beginNewDictation()
        service.captureSelectedTextContext(generation: generation)
        service.clearCapturedContexts()
        let context = await service.volatileContextSection()

        #expect(!context.contains("CURRENTLY_SELECTED_TEXT"))
        _ = container
    }

    // MARK: - Dictation-generation gating (X1 round-2: genuinely overlapping captures)

    /// A capture call made with an EXPLICITLY stale generation number (a
    /// newer dictation has already started by the time it's called) must be
    /// rejected at entry — it never even installs a slot, let alone one a
    /// reader could see.
    @Test("captureSelectedTextContext called with an already-stale generation installs nothing")
    func staleGenerationParameterInstallsNothing() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)

        let genOne = service.beginNewDictation()
        _ = service.beginNewDictation() // a newer dictation has already started

        service.selectedTextProvider = { "must never be installed" }
        service.captureSelectedTextContext(generation: genOne)

        let context = await service.volatileContextSection()
        #expect(!context.contains("must never be installed"))
        _ = container
    }

    /// The genuinely OVERLAPPING race: dictation one's capture is issued
    /// (passes its entry check — no newer dictation exists yet) and its fetch
    /// is still in flight when dictation two starts and completes its OWN
    /// capture. Dictation one's slow fetch resolving LATER, in the
    /// background, must never overwrite dictation two's already-current slot
    /// — this is what the slot-REPLACEMENT design (a fresh `SelectedTextSlot`
    /// per valid call, never mutated in place) guarantees. Unlike the
    /// previous version of this test, dictation two starts and is read
    /// BEFORE dictation one's fetch resolves, so this actually exercises the
    /// overlap instead of two sequential, non-overlapping captures.
    @Test("an in-flight overlapping capture from an older dictation never overwrites a newer one's slot")
    func overlappingCaptureFromOlderDictationNeverOverwritesNewerSlot() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)

        let genOne = service.beginNewDictation()
        service.selectedTextProvider = {
            try? await Task.sleep(nanoseconds: 500_000_000) // still in flight when dictation two starts
            return "dictation one — arrives late"
        }
        service.captureSelectedTextContext(generation: genOne) // passes its entry check — genOne IS current here

        let genTwo = service.beginNewDictation() // dictation two starts WHILE dictation one's fetch is still running
        service.selectedTextProvider = { "dictation two — arrives fast" }
        service.captureSelectedTextContext(generation: genTwo)

        // Read dictation two's context BEFORE dictation one's slow fetch can
        // possibly have resolved — this is the actual overlap.
        let contextDuringOverlap = await service.volatileContextSection()
        #expect(contextDuringOverlap.contains("dictation two — arrives fast"))
        #expect(!contextDuringOverlap.contains("dictation one"))

        // Let dictation one's stale fetch actually finish in the background
        // and confirm it changed nothing.
        try? await Task.sleep(nanoseconds: 700_000_000)
        let contextAfterStaleFetchResolves = await service.volatileContextSection()
        #expect(contextAfterStaleFetchResolves.contains("dictation two — arrives fast"))
        #expect(!contextAfterStaleFetchResolves.contains("dictation one"))
        _ = container
    }

    @Test("captureClipboardContext with a stale generation does not overwrite the current clipboard capture")
    func staleGenerationClipboardCaptureIsNoOp() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.useClipboardContext = true
        service.lastCapturedClipboard = "sentinel — must survive the stale write"

        let genOne = service.beginNewDictation()
        _ = service.beginNewDictation() // supersede

        service.captureClipboardContext(generation: genOne)
        #expect(service.lastCapturedClipboard == "sentinel — must survive the stale write")

        service.useClipboardContext = false
        service.lastCapturedClipboard = nil
        _ = container
    }

    // MARK: - Multi-reader safety (X1 round-3: SelectedTextSlot must not be single-reader)

    /// Regression: a single shared `pendingContinuation` let a second
    /// concurrent `read()` silently overwrite the first reader's
    /// continuation, hanging the first reader forever — reachable in
    /// practice since the live pipeline and a file/history re-enhance can
    /// both call `enhance(...)` (hence `volatileContextSection()`) around the
    /// same time. With `async let` racing two readers against the SAME slow
    /// provider, this test would hang indefinitely on the old single-slot
    /// implementation; with the waiter dictionary, both resolve correctly.
    @Test("two concurrent readers of the same capture both resolve, neither hangs")
    func concurrentReadersBothResolve() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.selectedTextProvider = {
            try? await Task.sleep(nanoseconds: 150_000_000) // long enough that both reads start first
            return "shared selection"
        }

        let generation = service.beginNewDictation()
        service.captureSelectedTextContext(generation: generation)

        async let readerA = service.volatileContextSection()
        async let readerB = service.volatileContextSection()
        let (contextA, contextB) = await (readerA, readerB)

        #expect(contextA.contains("shared selection"))
        #expect(contextB.contains("shared selection"))
        _ = container
    }
}
