import Foundation
import SwiftData

/// W12.E Scratchpad document. One per tab. Plain-text content with auto-save
/// (debounced 800ms) and per-document version history (50-cap FIFO via
/// `ScratchpadVersion`). Local-only (no CloudKit). See plan
/// `docs/superpowers/plans/W12E-scratchpad.md` §Migration policy #1.
@Model
final class ScratchpadDocument {
    var id: UUID
    var title: String
    var content: String
    var tabIndex: Int
    var createdAt: Date
    var updatedAt: Date

    /// Cascade delete-rule: when a document is deleted, its version snapshots
    /// die with it. Bounded count (Migration policy #7); blast radius is
    /// per-document.
    @Relationship(deleteRule: .cascade, inverse: \ScratchpadVersion.document)
    var versions: [ScratchpadVersion] = []

    init(title: String = "Untitled",
         content: String = "",
         tabIndex: Int = 0) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.tabIndex = tabIndex
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
