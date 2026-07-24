import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case models
    case vocabulary
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .models: return "Models"
        case .vocabulary: return "Vocabulary"
        case .advanced: return "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "command"
        case .models: return "cpu"
        case .vocabulary: return "character.book.closed"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

struct SettingsWindow: View {
    var body: some View {
        SettingsContentView()
    }
}
