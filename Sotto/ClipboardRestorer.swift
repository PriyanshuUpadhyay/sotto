import AppKit

/// Owns the timed clipboard restore that follows a paste. Main thread only.
///
/// A restore puts the user's clipboard back only when the clipboard still
/// holds the text that the latest paste put there. If the user copies
/// something during the delay, or a newer paste starts, the stale restore
/// stands down. A paste that starts while the previous paste's text is still
/// on the clipboard keeps the user's original snapshot, so two quick
/// dictations restore what the user had, not the first dictation.
/// Same design as Hex's `ClipboardRestore` (anomalyco/hex `src/paste.rs`, MIT).
final class ClipboardRestorer {
    typealias Snapshot = [(NSPasteboard.PasteboardType, Data)]

    static let shared = ClipboardRestorer(pasteboard: .general)

    private let pasteboard: NSPasteboard
    private var generation = 0
    private var original: Snapshot?
    private var insertedChangeCount: Int?

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    /// Records a paste. Call after the paste text is on the clipboard.
    /// `previousChangeCount` is the clipboard's change count before that write.
    /// Returns the token to pass to `restore(_:)`.
    func register(previous: Snapshot, previousChangeCount: Int) -> Int {
        generation &+= 1
        if insertedChangeCount != previousChangeCount {
            original = previous
        }
        insertedChangeCount = pasteboard.changeCount
        return generation
    }

    /// Records a paste whose text stays on the clipboard. A pending restore
    /// stands down, and no older snapshot can come back later.
    func keep() {
        generation &+= 1
        original = nil
        insertedChangeCount = nil
    }

    func restore(_ token: Int) {
        guard token == generation else { return }
        defer {
            original = nil
            insertedChangeCount = nil
        }
        guard pasteboard.changeCount == insertedChangeCount,
              let snapshot = original, !snapshot.isEmpty else { return }
        pasteboard.clearContents()
        for (type, data) in snapshot {
            pasteboard.setData(data, forType: type)
        }
    }
}
