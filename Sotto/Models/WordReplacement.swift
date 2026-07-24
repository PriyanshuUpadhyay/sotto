import Foundation
import SwiftData

@Model
final class WordReplacement {
    var id: UUID = UUID()
    var originalText: String = ""
    var replacementText: String = ""
    var dateAdded: Date = Date()
    var isEnabled: Bool = true
    /// Manual ordering position for drag-reorder (P3.D). Lower = earlier.
    /// Default 0; new entries assigned `currentMax + 1` at insert site.
    /// CloudKit-safe (has default).
    var sortOrder: Int = 0

    init(originalText: String, replacementText: String, dateAdded: Date = Date(), isEnabled: Bool = true, sortOrder: Int = 0) {
        self.originalText = originalText
        self.replacementText = replacementText
        self.dateAdded = dateAdded
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }
}
