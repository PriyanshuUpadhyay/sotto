import SwiftUI
import AppKit

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

/// The app's `Settings` scene (⌘, / the Settings menu item). Settings is no
/// longer a surface of its own — every page is a row in the main window's flat
/// sidebar — so this scene just forwards to the General row and closes.
struct SettingsWindow: View {
    /// The side effect the scene performs when it appears, factored out so the
    /// forwarding is unit-testable without a scene.
    @MainActor
    static func openMainWindowOnGeneral() {
        SottoWindowCoordinator.shared.open(settingsTab: .general)
    }

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            // WindowAccessor, not onAppear: the empty scene window has to be
            // closed once AppKit has actually created it.
            .background(WindowAccessor { window in
                Self.openMainWindowOnGeneral()
                window.close()
            })
    }
}
