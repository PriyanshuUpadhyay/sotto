import Foundation
import SwiftData

enum EditKind: String, Codable, CaseIterable {
    case spelling, formatting, style, semantic   // semantic is discarded by the gate
}

/// Which explicit post-paste control produced this record.
/// `.revertRaw` = raw preferred over enhancement. `.thumbsDown` = enhancement
/// bad, no correction. `.edit` = user supplied a corrected final text.
/// `.acceptedUnchanged` = review editor confirmed with final == enhanced (the
/// enhancement was accepted as-is) — kept so the zero-edit rate is measurable.
/// Retention is type-agnostic (oldest-first) so the rate's sample stays unbiased.
enum EditSignalSource: String, Codable, CaseIterable {
    case revertRaw, thumbsDown, edit, acceptedUnchanged

    /// True when the signal means the pasted text was CHANGED after paste — a
    /// real edit (`.edit` = corrected text, `.revertRaw` = swapped to the raw
    /// transcript). `.acceptedUnchanged` and `.thumbsDown` leave the pasted text
    /// intact, so they do not count against the zero-edit rate.
    var indicatesEdit: Bool {
        switch self {
        case .edit, .revertRaw: return true
        case .thumbsDown, .acceptedUnchanged: return false
        }
    }
}

@Model
final class EnhancementEditRecord {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var rawText: String = ""
    var enhancedText: String = ""
    var finalText: String = ""
    var appBundleID: String?
    var transcriptionID: UUID = UUID()
    /// Hash of normalized `enhancedText` captured at paste time — race-detection.
    var enhancedHash: String = ""
    var editKindRaw: String = EditKind.style.rawValue
    var signalSourceRaw: String = EditSignalSource.edit.rawValue
    var analyzed: Bool = false

    var editKind: EditKind { EditKind(rawValue: editKindRaw) ?? .style }
    var signalSource: EditSignalSource { EditSignalSource(rawValue: signalSourceRaw) ?? .edit }

    init(rawText: String, enhancedText: String, finalText: String,
         appBundleID: String?, transcriptionID: UUID,
         enhancedHash: String, editKind: EditKind,
         signalSource: EditSignalSource = .edit) {
        self.id = UUID()
        self.timestamp = Date()
        self.rawText = rawText
        self.enhancedText = enhancedText
        self.finalText = finalText
        self.appBundleID = appBundleID
        self.transcriptionID = transcriptionID
        self.enhancedHash = enhancedHash
        self.editKindRaw = editKind.rawValue
        self.signalSourceRaw = signalSource.rawValue
        self.analyzed = false
    }
}
