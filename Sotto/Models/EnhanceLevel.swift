import Foundation

/// Enhancement on/off gate. `.none` bypasses enhance entirely; `.light`
/// injects the single fixed "Light cleanup" directive into the system prompt.
/// Multi-level intensity (medium/high) was removed when the enhancement
/// surface collapsed to one AFM/Light path.
enum EnhanceLevel: String, Codable, CaseIterable, Equatable, Hashable {
    case none
    case light

    /// First-run + migrated default. Existing users with the old
    /// `isAIEnhancementEnabled = true` (or a stale medium/high level) land here.
    static let `default`: EnhanceLevel = .light

    /// Short label for status surfaces.
    var displayName: String {
        switch self {
        case .none:  return "None"
        case .light: return "Light"
        }
    }

    /// Map the legacy bool to a level. Used by Codable migration paths.
    static func from(legacyBool: Bool) -> EnhanceLevel {
        legacyBool ? .light : .none
    }

    /// Migrate a persisted raw value, folding the removed `medium`/`high`
    /// levels onto `.light` so an upgrade keeps enhancement enabled.
    static func migrating(rawValue raw: String) -> EnhanceLevel? {
        switch raw {
        case "none":            return EnhanceLevel.none
        case "light":           return .light
        case "medium", "high":  return .light
        default:                return nil
        }
    }
}
