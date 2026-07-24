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
        case .phosphor: return Color(red: 0xb9/255.0, green: 0xf2/255.0, blue: 0x7e/255.0)
        case .ice:      return Color(red: 0x8a/255.0, green: 0xd8/255.0, blue: 0xff/255.0)
        case .violet:   return Color(red: 0xc9/255.0, green: 0xa8/255.0, blue: 0xff/255.0)
        case .amber:    return Color(red: 0xff/255.0, green: 0xd2/255.0, blue: 0x7f/255.0)
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

/// Root wrapper for independently-hosted surfaces (NSHostingController
/// panels: mini recorder, compose review). They sit outside the observed
/// window roots, so without this an accent change never invalidates them.
struct AccentObserving<Content: View>: View {
    @ObservedObject private var accent = AccentStore.shared
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.tint(Brand.tint)
    }
}
