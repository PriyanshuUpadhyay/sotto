import Foundation
import SwiftData

/// W12.C voice-snippet expansion. User-curated trigger → expansion pairs.
/// Pre-enhance pipeline pass replaces every `\b<trigger>\b` occurrence with
/// the expansion before the AI cleanup pass runs. See plan
/// `docs/superpowers/plans/W12C-voice-snippets.md` §Migration policy #2.
@Model
final class Snippet {
    /// Stable identifier (CloudKit-safe should sync land later).
    var id: UUID = UUID()

    /// Short typed token. Case-sensitive uniqueness; 1-32 chars matching
    /// `^[A-Za-z0-9;:_./@-]{1,32}$`. Enforced at insert / update via
    /// `Snippet.validate(trigger:against:)`. See plan §Migration policy #6
    /// (lead-locked answer #1: include `:` from the start for `:date`-style
    /// triggers).
    var trigger: String = ""

    /// Long-form text spliced in place of the trigger. Plain text only;
    /// no variable substitution in v1 (see plan §Out of scope).
    var expansion: String = ""

    /// Optional user-curated tags for grouping / filtering. Stored as a
    /// SwiftData-encoded `[String]` per plan §Migration policy #4.
    var tags: [String] = []

    /// User-controlled enable / disable; gates whether the trigger fires.
    /// Disabled snippets remain in the table for round-trip but are skipped
    /// by `SnippetExpansionService.expand(...)`.
    var isEnabled: Bool = true

    /// Insert timestamp (used for stable ordering in CRUD UI).
    var createdAt: Date = Date()

    /// Last-edit timestamp (touched on every update).
    var updatedAt: Date = Date()

    init(
        trigger: String,
        expansion: String,
        tags: [String] = [],
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = UUID()
        self.trigger = trigger
        self.expansion = expansion
        self.tags = tags
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

extension Snippet {
    /// Permitted character set per plan §Migration policy #6 + lead-locked
    /// answer #1 (includes `:` for `:date`-style triggers).
    /// Anchored full-string match; rejects empty + over-length.
    static let triggerPattern = #"^[A-Za-z0-9;:_./@\-]{1,32}$"#

    /// Validation result. `nil` permits the save; a non-nil case is the
    /// user-facing reason rendered inline in the editor sheet.
    enum ValidationError: LocalizedError, Equatable {
        case empty
        case malformed
        case duplicate(existingTrigger: String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Trigger cannot be empty."
            case .malformed:
                return "Trigger may only contain letters, numbers, and these symbols: ; : _ . / @ -"
            case .duplicate(let existing):
                return "Trigger '\(existing)' is already in use. Pick a different trigger."
            }
        }
    }

    /// Validate a candidate trigger against the existing table.
    /// Case-sensitive per plan §Migration policy #5.
    static func validate(
        trigger candidate: String,
        against existing: [Snippet],
        editingId: UUID? = nil
    ) -> ValidationError? {
        if candidate.isEmpty { return .empty }
        guard candidate.range(of: triggerPattern, options: .regularExpression) != nil else {
            return .malformed
        }
        // Case-sensitive duplicate check; allow an in-place edit to keep its
        // own trigger.
        if let dup = existing.first(where: { $0.trigger == candidate && $0.id != editingId }) {
            return .duplicate(existingTrigger: dup.trigger)
        }
        return nil
    }
}
