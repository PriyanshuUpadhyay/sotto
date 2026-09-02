import Foundation

/// One searchable Settings entry: a section in a tab, identified by its tab and
/// a human-readable label, plus the names of the controls that section holds.
/// The index still holds exactly one entry per section — control names are
/// keywords ON the section entry, never live control values.
struct SettingsSearchResult: Equatable, Identifiable {
    let tab: SettingsTab
    let label: String
    /// What the section's own controls are called, so a query naming a control
    /// ("haptic", "export") finds the section that owns it.
    var keywords: [String] = []
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
        // No Models or Vocabulary entries: both graduated to first-class window
        // destinations and are no longer Settings rail rows, so neither is
        // reachable from the Settings search field. The command palette reaches
        // Dictionary through `CommandRegistry.dictionaryCommands` instead.
        var entries: [SettingsSearchResult] = []
        entries += GeneralTab.GeneralTabSection.allCases.map { SettingsSearchResult(tab: .general, label: $0.searchLabel, keywords: $0.searchKeywords) }
        entries += ShortcutsTab.ShortcutsTabSection.allCases.map { SettingsSearchResult(tab: .shortcuts, label: $0.searchLabel, keywords: $0.searchKeywords) }
        entries += AdvancedTab.AdvancedTabSection.allCases.map { SettingsSearchResult(tab: .advanced, label: $0.searchLabel, keywords: $0.searchKeywords) }
        return entries
    }

    /// Pure, testable filter. An empty (or whitespace-only) query returns every
    /// index entry. Otherwise it returns entries whose section label, tab title
    /// or control keywords contain the query, case-insensitively. Still one
    /// entry per section; no live control values are consulted.
    func filter(_ query: String) -> [SettingsSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.index }
        return Self.index.filter { entry in
            entry.label.localizedCaseInsensitiveContains(trimmed)
                || entry.tab.title.localizedCaseInsensitiveContains(trimmed)
                || entry.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
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

// MARK: - Section labels and control keywords
//
// Human labels — and the names of the controls each section holds — for every
// tab's section descriptor. Each switch is EXHAUSTIVE over its enum, so adding
// or removing a section case is a compile error here — the search index stays
// in lockstep with the tabs' real composition.

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

    var searchKeywords: [String] {
        switch self {
        case .audioInput: return ["microphone", "mic", "input device", "device priority"]
        case .soundFeedback: return ["sound", "haptics", "haptic feedback", "mute", "resume delay"]
        case .launchAtLogin: return ["startup", "start automatically", "login item"]
        case .hideDock: return ["dock icon", "menu bar only"]
        case .permissionsStatus: return ["accessibility", "screen recording", "microphone access"]
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

    var searchKeywords: [String] {
        switch self {
        case .primaryShortcuts: return ["hotkey", "keyboard", "record", "push to talk"]
        case .paste: return ["clipboard", "hotkey"]
        case .retry: return ["hotkey", "re-run"]
        case .commandPalette: return ["hotkey", "command k"]
        case .customCancel: return ["stop", "escape", "hotkey"]
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
        case .fillerWords: return "Filler Words"
        }
    }

    var searchKeywords: [String] {
        switch self {
        case .dictionary: return ["vocabulary", "terms", "spelling", "custom words"]
        case .wordReplacements: return ["replace", "substitution", "rewrite"]
        case .fillerWords: return ["um", "uh", "hmm"]
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

    var searchKeywords: [String] {
        switch self {
        case .privacy: return ["auto-delete", "cleanup", "retention", "audio files", "transcripts"]
        case .backup: return ["export", "import", "restore"]
        }
    }
}

