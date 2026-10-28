import Foundation
import KeyboardShortcuts

struct GeneralSettings: Codable {
    let toggleMiniRecorderShortcut: KeyboardShortcuts.Shortcut?
    let retryLastTranscriptionShortcut: KeyboardShortcuts.Shortcut?
    let selectedHotkey1RawValue: String?
    let launchAtLoginEnabled: Bool?
    let isMenuBarOnly: Bool?
    let isTranscriptionCleanupEnabled: Bool?
    let transcriptionRetentionMinutes: Int?
    let isAudioCleanupEnabled: Bool?
    let audioRetentionPeriod: Int?

    let isSoundFeedbackEnabled: Bool?
    let isSystemMuteEnabled: Bool?
    let isPauseMediaEnabled: Bool?
    let audioResumptionDelay: Double?
    let isTextFormattingEnabled: Bool?
    let isExperimentalFeaturesEnabled: Bool?
    let restoreClipboardAfterPaste: Bool?
    let clipboardRestoreDelay: Double?
    let useAppleScriptPaste: Bool?
}

// Simple codable struct for vocabulary words (for export/import only)
struct VocabularyWordData: Codable {
    let word: String
}

/// W12.C snippet export transit type. Plain Codable mirror of the SwiftData
/// `Snippet` @Model — that class can't conform to Codable directly.
/// See plan §Migration policy #8.
struct SnippetExportData: Codable {
    let trigger: String
    let expansion: String
    let tags: [String]?
    let isEnabled: Bool?
    let createdAt: Date?
    let updatedAt: Date?
}

struct SottoExportedSettings: Codable {
    let version: String
    /// Legacy field — the multi-prompt system was removed. Kept optional so old
    /// export files still decode; never written on export, never applied on import.
    let customPrompts: [CustomPrompt]?
    let vocabularyWords: [VocabularyWordData]?
    let wordReplacements: [String: String]?
    let generalSettings: GeneralSettings?
    let snippets: [SnippetExportData]?  // W12.C
}
