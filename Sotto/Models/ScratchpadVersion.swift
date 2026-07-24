import Foundation
import SwiftData

/// W12.E version snapshot of a Scratchpad document. Captured every 30s of
/// active typing OR on tab switch / window close. FIFO-evicted at 50 per
/// document. See plan `docs/superpowers/plans/W12E-scratchpad.md`
/// §Migration policy #6 + #7.
@Model
final class ScratchpadVersion {
    var id: UUID
    var content: String
    var capturedAt: Date

    var document: ScratchpadDocument?

    init(content: String, document: ScratchpadDocument) {
        self.id = UUID()
        self.content = content
        self.capturedAt = Date()
        self.document = document
    }
}
