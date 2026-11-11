import AppKit
import Testing
@testable import Sotto

/// Each test drives a private named pasteboard the way `CursorPaster` drives
/// the general one: snapshot, write the dictation, register, then restore.
@MainActor
struct ClipboardRestorerTests {
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("sotto.tests.\(UUID().uuidString)"))

    private func write(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func snapshot() -> ClipboardRestorer.Snapshot {
        pasteboard.pasteboardItems?.flatMap { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
    }

    /// Simulates one paste: what `CursorPaster.pasteAtCursor` does before its timed restore.
    private func paste(_ text: String, with restorer: ClipboardRestorer) -> Int {
        let previous = snapshot()
        let previousChangeCount = pasteboard.changeCount
        write(text)
        return restorer.register(previous: previous, previousChangeCount: previousChangeCount)
    }

    @Test func restoresTheUsersClipboardAfterAPaste() {
        let restorer = ClipboardRestorer(pasteboard: pasteboard)
        write("user text")
        let token = paste("dictation", with: restorer)
        restorer.restore(token)
        #expect(pasteboard.string(forType: .string) == "user text")
    }

    @Test func keepsWhatTheUserCopiedDuringTheDelay() {
        let restorer = ClipboardRestorer(pasteboard: pasteboard)
        write("user text")
        let token = paste("dictation", with: restorer)
        write("copied during delay")
        restorer.restore(token)
        #expect(pasteboard.string(forType: .string) == "copied during delay")
    }

    @Test func twoQuickPastesRestoreTheOriginalClipboard() {
        let restorer = ClipboardRestorer(pasteboard: pasteboard)
        write("user text")
        let first = paste("first dictation", with: restorer)
        let second = paste("second dictation", with: restorer)
        restorer.restore(first)
        #expect(pasteboard.string(forType: .string) == "second dictation")
        restorer.restore(second)
        #expect(pasteboard.string(forType: .string) == "user text")
    }
}
