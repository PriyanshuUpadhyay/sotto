import Foundation

enum DeepLinkTarget: Equatable {
    case settings(SettingsTab)
    case sottoWindow(SottoWindowTab)
    case onboarding
}

enum DeepLinkRouter {
    static func target(for destination: String) -> DeepLinkTarget? {
        switch destination {
        case "Settings":
            return .settings(.general)
        case "Models", "AI Models", "Enhancement":
            return .settings(.models)
        case "Permissions":
            return .onboarding
        case "History":
            return .sottoWindow(.history)
        default:
            return nil
        }
    }
}
