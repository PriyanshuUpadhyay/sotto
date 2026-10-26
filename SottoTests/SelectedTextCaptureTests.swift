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
///
/// The grace timer is injected too (`selectedTextGraceSleep`), so the timing
/// tests below never measure wall-clock time: they decide whether the grace
/// period "elapses" and gate the fake fetch themselves. A regression that
/// would only show as a hang carries a `.timeLimit` so it fails instead of
/// stalling the run.
@MainActor
struct SelectedTextCaptureTests {

    /// One-shot gate the test opens itself — replaces a sleep as the way to
    /// order two tasks. Deliberately not cancellation-aware, like a stuck AX call.
    private actor Latch {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func open() {
            isOpen = true
            let pending = waiters
            waiters = []
            for continuation in pending { continuation.resume() }
        }

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    /// Counts grace-timer registrations. Every reader that starts waiting on a
    /// slot arms one, so `armed(2)` is a deterministic "both readers are now
    /// blocked" signal — no sleep needed to let them get there.
    private actor GraceTimers {
        private var count = 0
        private let released = Latch()
        private var thresholds: [Int: Latch] = [:]

        func arm() async {
            count += 1
            await thresholds[count]?.open()
        }

        func armed(_ n: Int) async {
            if count >= n { return }
            let latch = thresholds[n] ?? Latch()
            thresholds[n] = latch
            await latch.wait()
        }

        /// What the grace timer awaits: never returns until the test releases it.
        func hold() async { await released.wait() }
        func release() async { await released.open() }
    }

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

    /// The grace timer never fires here, so only the write can resolve the read —
    /// a slow Mac can't turn the instant fetch into a timeout.
    @Test("captured selected text appears in the volatile context section")
    func capturedSelectedTextAppearsInContext() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        let graceHeld = Latch()
        service.selectedTextGraceSleep = { _ in await graceHeld.wait() }
        service.selectedTextProvider = { "some selected text" }

        let generation = service.beginNewDictation()
        service.captureSelectedTextContext(generation: generation)
        let context = await service.volatileContextSection()

        #expect(context.contains("<CURRENTLY_SELECTED_TEXT>\nsome selected text\n</CURRENTLY_SELECTED_TEXT>"))
        await graceHeld.open()
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
    /// problem, and this test is what proves it. The fetch here is blocked on
    /// a gate that ignores cancellation and stays shut until the end of the
    /// test, and the grace timer fires at once: the only way out is the timeout.
    @Test("a slow fetch past the grace period yields no block, not a hang", .timeLimit(.minutes(1)))
    func slowFetchTimesOutGracefully() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        let stuck = Latch()
        service.selectedTextProvider = {
            await stuck.wait()
            return "too slow to matter"
        }
        service.selectedTextGraceSleep = { _ in } // grace period is over at once

        let generation = service.beginNewDictation()
        service.captureSelectedTextContext(generation: generation)
        let context = await service.volatileContextSection()

        #expect(!context.contains("CURRENTLY_SELECTED_TEXT"))
        await stuck.open() // let the background fetch finish
        _ = container
    }

    /// A fetch that finishes WELL within the grace period must not be held
    /// up waiting out the full grace window — the read returns as soon as
    /// the fetch task writes. The grace timer here never fires, so a read that
    /// waited for it would hang (caught by the time limit) rather than return.
    @Test("fast fetch delivers the captured value rather than timing out", .timeLimit(.minutes(1)))
    func fastFetchDeliversValueWithinGrace() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        let graceHeld = Latch()
        service.selectedTextGraceSleep = { _ in await graceHeld.wait() }
        service.selectedTextProvider = { "instant" }

        let generation = service.beginNewDictation()
        service.captureSelectedTextContext(generation: generation)
        let context = await service.volatileContextSection()

        // Receiving the VALUE proves the write-signal won the race: a grace
        // timeout resumes nil, never the value, so no wall-clock assertion is
        // needed (and any would flake under parallel-test main-actor load).
        #expect(context.contains("instant"))
        await graceHeld.open()
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
    /// is still in flight when dictation two starts and issues its OWN
    /// capture. Dictation one's slow fetch resolving LATER — here, even BEFORE
    /// dictation two's fetch does — must never land in dictation two's slot:
    /// this is what the slot-REPLACEMENT design (a fresh `SelectedTextSlot`
    /// per valid call, never mutated in place) guarantees. Dictation two's
    /// reader is already blocked on its slot (proved by its grace timer
    /// arming) when dictation one's fetch returns, so this actually exercises
    /// the overlap instead of two sequential, non-overlapping captures.
    @Test("an in-flight overlapping capture from an older dictation never overwrites a newer one's slot", .timeLimit(.minutes(1)))
    func overlappingCaptureFromOlderDictationNeverOverwritesNewerSlot() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        let timers = GraceTimers()
        service.selectedTextGraceSleep = { _ in // the grace period never ends on its own
            await timers.arm()
            await timers.hold()
        }

        let fetchOne = Latch()
        let fetchOneReturned = Latch()
        let fetchTwo = Latch()

        let genOne = service.beginNewDictation()
        service.selectedTextProvider = {
            await fetchOne.wait() // still in flight when dictation two starts
            await fetchOneReturned.open()
            return "dictation one — arrives late"
        }
        service.captureSelectedTextContext(generation: genOne) // passes its entry check — genOne IS current here

        let genTwo = service.beginNewDictation() // dictation two starts WHILE dictation one's fetch is still running
        service.selectedTextProvider = {
            await fetchTwo.wait()
            return "dictation two — arrives last"
        }
        service.captureSelectedTextContext(generation: genTwo)

        async let duringOverlap = service.volatileContextSection()
        await timers.armed(1) // dictation two's reader is now blocked on its slot

        // Dictation one's stale fetch finishes first. Its write goes to its own
        // orphaned slot (a slot shared with dictation two would be filled now,
        // and win). Nothing can observe the orphaned write landing, so give it
        // a few turns; if it lands later, the test still passes, it just checks less.
        await fetchOne.open()
        await fetchOneReturned.wait()
        for _ in 0..<20 { await Task.yield() }

        await fetchTwo.open()
        let contextDuringOverlap = await duringOverlap
        #expect(contextDuringOverlap.contains("dictation two — arrives last"))
        #expect(!contextDuringOverlap.contains("dictation one"))

        let contextAfterStaleFetchResolves = await service.volatileContextSection()
        #expect(contextAfterStaleFetchResolves.contains("dictation two — arrives last"))
        #expect(!contextAfterStaleFetchResolves.contains("dictation one"))

        await timers.release()
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
    /// same time. With `async let` racing two readers against the SAME gated
    /// provider, this test would hang indefinitely on the old single-slot
    /// implementation (caught by the time limit); with the waiter dictionary,
    /// both resolve correctly. The fetch is only released once both readers'
    /// grace timers have armed, i.e. once both are actually blocked, and the
    /// grace timer itself never fires — only the write can resolve them.
    @Test("two concurrent readers of the same capture both resolve, neither hangs", .timeLimit(.minutes(1)))
    func concurrentReadersBothResolve() async {
        let container = Self.makeContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        let timers = GraceTimers()
        service.selectedTextGraceSleep = { _ in
            await timers.arm()
            await timers.hold()
        }
        let fetch = Latch()
        service.selectedTextProvider = {
            await fetch.wait()
            return "shared selection"
        }

        let generation = service.beginNewDictation()
        service.captureSelectedTextContext(generation: generation)

        async let readerA = service.volatileContextSection()
        async let readerB = service.volatileContextSection()
        await timers.armed(2) // both readers are blocked on the slot
        await fetch.open()
        let (contextA, contextB) = await (readerA, readerB)

        #expect(contextA.contains("shared selection"))
        #expect(contextB.contains("shared selection"))

        await timers.release()
        _ = container
    }
}
