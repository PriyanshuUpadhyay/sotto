import Testing
import Foundation
import SwiftData
import AppKit
@testable import Sotto

// MARK: - ReviewTrayTests
//
// Pure-logic coverage for the post-paste Review Tray (W4 Bet A). The
// paste/reactivate keystroke paths are not unit-testable; what IS pure is the
// CursorPaster clipboard stash → restore round-trip, the non-transient copy,
// and the most-recent-`Transcription` query that drives Re-enhance.

@MainActor
@Suite(.serialized)
struct ReviewTrayTests {

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

    /// Capture the current `NSPasteboard.general` contents the same way
    /// `CursorPaster.pasteAtCursor` does, for stash round-trip tests.
    private static func captureGeneralPasteboard() -> [(NSPasteboard.PasteboardType, Data)] {
        var saved: [(NSPasteboard.PasteboardType, Data)] = []
        for item in (NSPasteboard.general.pasteboardItems ?? []) {
            for type in item.types {
                if let data = item.data(forType: type) {
                    saved.append((type, data))
                }
            }
        }
        return saved
    }

    // MARK: - Clipboard stash → restore

    @Test("restorePriorClipboard round-trips the stashed prior clipboard")
    func undoRestoresPriorClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("ORIGINAL", forType: .string)

        CursorPaster.lastPasteContext = CursorPaster.PasteContext(
            priorClipboard: Self.captureGeneralPasteboard(),
            targetApp: nil,
            appName: "TestApp"
        )

        // Simulate the paste overwriting the clipboard.
        pb.clearContents()
        pb.setString("PASTED-TEXT", forType: .string)
        #expect(pb.string(forType: .string) == "PASTED-TEXT")

        CursorPaster.restorePriorClipboard()
        #expect(pb.string(forType: .string) == "ORIGINAL")

        CursorPaster.lastPasteContext = nil
    }

    @Test("restorePriorClipboard is a no-op when nothing was stashed")
    func undoNoOpWhenUnstashed() {
        CursorPaster.lastPasteContext = nil
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("CURRENT", forType: .string)

        CursorPaster.restorePriorClipboard()
        #expect(pb.string(forType: .string) == "CURRENT")
    }

    @Test("copyToClipboard puts text back non-transiently")
    func copyPutsTextOnClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("SOMETHING-ELSE", forType: .string)

        CursorPaster.copyToClipboard("PASTED-RESULT")
        #expect(pb.string(forType: .string) == "PASTED-RESULT")
        // Non-transient → no TransientType marker present.
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        #expect(pb.data(forType: transient) == nil)
    }

    // MARK: - Most-recent transcription query

    @Test("mostRecent selects the newest Transcription by timestamp")
    func mostRecentSelectsNewest() {
        let container = Self.makeContainer()
        let ctx = container.mainContext

        let base = Date(timeIntervalSince1970: 1_000_000)
        let oldest = Transcription(text: "oldest", duration: 1)
        oldest.timestamp = base
        let newest = Transcription(text: "newest", duration: 1)
        newest.timestamp = base.addingTimeInterval(120)
        let middle = Transcription(text: "middle", duration: 1)
        middle.timestamp = base.addingTimeInterval(60)

        // Insert out of order to prove the sort, not insertion order, wins.
        ctx.insert(oldest)
        ctx.insert(newest)
        ctx.insert(middle)
        try? ctx.save()

        let result = RecentTranscriptionQuery.mostRecent(in: ctx)
        #expect(result?.id == newest.id)
        #expect(result?.text == "newest")
        _ = container
    }

    @Test("mostRecent returns nil for an empty store")
    func mostRecentNilWhenEmpty() {
        let container = Self.makeContainer()
        let result = RecentTranscriptionQuery.mostRecent(in: container.mainContext)
        #expect(result == nil)
        _ = container
    }
}
