import SwiftUI

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var glassAppearance: GlassAppearance? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .onyx
        }
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()
    private static let key = "SottoAppearanceChoice"

    private let defaults: UserDefaults

    @Published var choice: AppearanceChoice {
        didSet {
            defaults.set(choice.rawValue, forKey: Self.key)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initialChoice = defaults.string(forKey: Self.key)
            .flatMap(AppearanceChoice.init(rawValue:)) ?? .system
        choice = initialChoice
    }
}
