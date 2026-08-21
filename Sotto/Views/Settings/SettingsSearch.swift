import Foundation

/// One searchable Settings entry: a section in a tab, identified by its tab and
/// a human-readable label. v1 indexes section LABELS only — never live control
/// values — so the index holds exactly one entry per section.
struct SettingsSearchResult: Equatable, Identifiable {
    let tab: SettingsTab
    let label: String
    var id: String { "\(tab.rawValue):\(label)" }
}

struct SettingsSearch {
    var query: String = ""

    /// The full search index: one entry per section across all tabs, derived
    /// from each tab's section enum `allCases`. Because it is built straight
    /// from the descriptor enums, `index.count` equals the sum of section cases
    /// across the tabs by construction — it cannot drift deeper into per-control
    /// values.
    static let index: [SettingsSearchResult] = buildIndex()

    private static func buildIndex() -> [SettingsSearchResult] {
        // No Models entries: Models graduated to a first-class window
        // destination (2026-07 revamp) and is no longer a Settings rail row.
        var entries: [SettingsSearchResult] = []
        entries += GeneralTab.GeneralTabSection.allCases.map { SettingsSearchResult(tab: .general, label: $0.searchLabel) }
        entries += ShortcutsTab.ShortcutsTabSection.allCases.map { SettingsSearchResult(tab: .shortcuts, label: $0.searchLabel) }
        entries += VocabularyTab.VocabularyTabSection.allCases.map { SettingsSearchResult(tab: .vocabulary, label: $0.searchLabel) }
        entries += AdvancedTab.AdvancedTabSection.allCases.map { SettingsSearchResult(tab: .advanced, label: $0.searchLabel) }
        return entries
    }

    /// Pure, testable filter. An empty (or whitespace-only) query returns every
    /// index entry. Otherwise it returns entries whose section label or tab
    /// title contains the query, case-insensitively. v1 = label/section match
    /// only; no live control values are consulted.
    func filter(_ query: String) -> [SettingsSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.index }
        return Self.index.filter { entry in
            entry.label.localizedCaseInsensitiveContains(trimmed)
                || entry.tab.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Whether a whole tab survives the current query — true when the tab itself
    /// matches or any of its sections do. Used to narrow the sidebar.
    func matches(_ tab: SettingsTab) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return filter(trimmed).contains { $0.tab == tab }
    }

    func filteredTabs() -> [SettingsTab] {
        SettingsTab.allCases.filter(matches)
    }
}

// MARK: - Section labels
//
// Human labels for each tab's section descriptor. Each switch is EXHAUSTIVE
// over its enum, so adding or removing a section case is a compile error here —
// the search index stays in lockstep with the tabs' real composition.

extension GeneralTab.GeneralTabSection {
    var searchLabel: String {
        switch self {
        case .audioInput: return "Audio Input"
        case .soundFeedback: return "Sound Feedback"
        case .launchAtLogin: return "Launch at Login"
        case .hideDock: return "Hide Dock Icon"
        case .permissionsStatus: return "Permissions"
        }
    }
}

extension ShortcutsTab.ShortcutsTabSection {
    var searchLabel: String {
        switch self {
        case .primaryShortcuts: return "Recorder Shortcuts"
        case .paste: return "Paste Last Transcription"
        case .retry: return "Retry Last Transcription"
        case .commandPalette: return "Command Palette"
        case .customCancel: return "Custom Cancel"
        }
    }
}

extension ModelsTab.ModelsTabSection {
    var searchLabel: String {
        switch self {
        case .transcription: return "Transcription Models"
        case .enhancement: return "Enhancement"
        }
    }
}

extension VocabularyTab.VocabularyTabSection {
    var searchLabel: String {
        switch self {
        case .dictionary: return "Dictionary"
        case .wordReplacements: return "Word Replacements"
        }
    }
}

extension AdvancedTab.AdvancedTabSection {
    var searchLabel: String {
        switch self {
        case .privacy: return "Privacy"
        case .backup: return "Backup & Restore"
        }
    }
}
