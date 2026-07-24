import Foundation

/// The single fixed enhancement prompt. The custom-prompts CRUD + multi-prompt
/// switching were removed when enhancement collapsed to one AFM/Light path;
/// enhancement now always runs on this one "Default" cleanup prompt.
enum PredefinedPrompts {
    /// Stable UUID for the fixed Default prompt. Retained so persisted
    /// `selectedPromptId` values and History rows that reference it stay valid.
    static let defaultPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static let defaultPrompt = CustomPrompt(
        id: defaultPromptId,
        title: "Default",
        promptText: AIPrompts.cleanupRules,
        icon: "checkmark.seal.fill",
        description: "Default cleanup for clarity and accuracy of the transcription",
        isPredefined: true
    )
}
