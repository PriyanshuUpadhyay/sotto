import Foundation

/// Raw + enhanced text for a transcript palette row. The palette pastes one or
/// the other into the captured app based on the ⌘ modifier (plain ⏎/click →
/// enhanced rewrite, ⌘⏎/⌘-click → raw transcript).
struct TranscriptPasteItem {
    let raw: String
    let enhanced: String?
}

/// One flat, runnable palette entry. No nesting — a single top-level list is
/// fuzzy-ranked and rendered. `requiresFocusRestore` marks paste/retry actions
/// that must re-focus the captured frontmost app before running. `transcript`
/// is set only on transcript rows, whose paste text is chosen by the controller
/// from the ⌘ modifier rather than the fixed `run` closure.
struct PaletteCommand: Identifiable {
    enum Category {
        case quickAction, transcript, model, prompt, navigate

        var label: String {
            switch self {
            case .quickAction: return "Action"
            case .transcript:  return "Transcript"
            case .model:       return "Model"
            case .prompt:      return "Prompt"
            case .navigate:    return "Navigate"
            }
        }
    }

    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let category: Category
    let requiresFocusRestore: Bool
    let run: () -> Void
    var transcript: TranscriptPasteItem? = nil
}
