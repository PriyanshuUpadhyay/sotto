import Foundation

/// 4-level enhancement intensity dial. Replaces the legacy
/// `isAIEnhancementEnabled: Bool` per W12.A (master plan §0 Q6=a).
/// `.none` bypasses enhance entirely; `.light`/`.medium`/`.high` inject a
/// per-level cleanup directive into the system prompt without changing the
/// model lineup. See plan
/// `docs/superpowers/plans/W12A-auto-cleanup-levels.md` §Migration policy #4.
enum EnhanceLevel: String, Codable, CaseIterable, Equatable, Hashable {
    case none
    case light
    case medium
    case high

    /// First-run + migrated default. Existing users with the old
    /// `isAIEnhancementEnabled = true` land here.
    static let `default`: EnhanceLevel = .medium

    /// Short label for picker cells.
    var displayName: String {
        switch self {
        case .none:   return "None"
        case .light:  return "Light"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    /// One-line description rendered below the picker. ~50-70 chars.
    var description: String {
        switch self {
        case .none:   return "Paste the raw transcript without AI cleanup."
        case .light:  return "Remove fillers and add punctuation. Keep wording exact."
        case .medium: return "Light cleanup plus grammar fixes. Default for most."
        case .high:   return "Aggressive cleanup with style polishing for clarity."
        }
    }

    /// Map the legacy bool to a level. Used by Codable migration paths.
    static func from(legacyBool: Bool) -> EnhanceLevel {
        legacyBool ? .medium : .none
    }
}
