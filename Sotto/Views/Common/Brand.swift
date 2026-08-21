import SwiftUI

/// The four user-selectable accents (2026-07 revamp, design-mockups/02).
/// Phosphor stays the default — the locked P0 value.
enum AccentChoice: String, CaseIterable, Identifiable {
    case phosphor
    case ice
    case violet
    case amber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phosphor: return "Phosphor"
        case .ice:      return "Ice"
        case .violet:   return "Violet"
        case .amber:    return "Amber"
        }
    }

    var color: Color {
        switch self {
        case .phosphor: return Palette.adaptive(light: 0x3d6b00, dark: 0xb9f27e)
        case .ice: return Palette.adaptive(light: 0x006b8f, dark: 0x8ad8ff)
        case .violet: return Palette.adaptive(light: 0x6941a5, dark: 0xc9a8ff)
        case .amber: return Palette.adaptive(light: 0x815000, dark: 0xffd27f)
        }
    }
}

/// Single owner of the stored accent choice. Window roots observe this so an
/// accent change re-renders their subtree — every `Palette.phosphor` /
/// `Brand.tint` read resolves through here dynamically.
final class AccentStore: ObservableObject {
    static let shared = AccentStore()
    private static let key = "SottoAccentChoice"

    private let defaults: UserDefaults

    @Published var choice: AccentChoice {
        didSet { defaults.set(choice.rawValue, forKey: Self.key) }
    }

    /// Injectable defaults so the missing/garbage-value fallback is testable;
    /// the app always uses `shared` (standard defaults).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choice = defaults.string(forKey: Self.key)
            .flatMap(AccentChoice.init(rawValue:)) ?? .phosphor
    }
}

/// The one Sotto brand accent. Wired as the app `accentColor` so native
/// windows get accent selection/toggles/focus *for free*, and the HUD uses the
/// same hue as its primary recording signal. (Council 2026-06-03.)
enum Brand {
    /// Resolves the user's stored accent (default: phosphor #b9f27e). Same
    /// value as `Palette.phosphor` — both read `AccentStore`.
    static var tint: Color { Palette.phosphor }
}

extension View {
    /// Apply the Sotto brand accent (selection, toggles, focus rings).
    func brandAccented() -> some View { self.tint(Brand.tint) }
}

/// Applies shared accent and appearance state to independent hosting roots.
struct AccentObserving<Content: View>: View {
    @ObservedObject private var accent = AccentStore.shared
    @ObservedObject private var appearance = AppearanceStore.shared
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .tint(Brand.tint)
            .preferredColorScheme(appearance.choice.colorScheme)
    }
}
