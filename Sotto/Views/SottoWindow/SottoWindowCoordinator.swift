import SwiftUI
import AppKit

/// The concrete action a deep-link destination resolves to. Pure value type so
/// the destination→action mapping is unit-testable without performing the side
/// effect (opening windows, presenting onboarding).
enum DeepLinkRoutingAction: Equatable {
    case openSettings(SettingsTab)
    case openSottoWindow(SottoWindowTab)
    case presentOnboarding
}

final class SottoWindowCoordinator: ObservableObject {
    static let shared = SottoWindowCoordinator()
    static let windowID = "sotto-main"

    @Published var pendingTab: SottoWindowTab?

    /// A staged Settings target: a tab, or a tab + section to scroll to.
    enum PendingSettingsTarget: Equatable {
        case tab(SettingsTab)
        case section(tab: SettingsTab, label: String)

        var tab: SettingsTab {
            switch self {
            case .tab(let tab), .section(let tab, _): return tab
            }
        }
    }

    /// Staged Settings target, mirroring `pendingTab`: the .selectSettingsTab /
    /// .selectSettingsSection notifications are lossy when the Sotto window's
    /// SettingsContentView isn't mounted yet, so `open(settingsTab:)` /
    /// `open(settingsSection:label:)` stage here and the IN-WINDOW instance
    /// consumes it on mount. One value — latest wins, no contradictory state.
    var pendingSettingsTarget: PendingSettingsTarget?

    /// Staged Dictionary section jump, mirroring `pendingSettingsTarget`: the
    /// .selectSettingsSection notification is equally lossy when the window's
    /// Dictionary destination isn't mounted yet.
    var pendingDictionarySection: String?

    private var opener: ((String) -> Void)?

    private init() {}

    func registerOpener(_ opener: @escaping (String) -> Void) {
        self.opener = opener
    }

    /// Open Settings targeting a specific tab. Stages the target for a not-yet-
    /// mounted in-window SettingsContentView AND posts the notification for a
    /// mounted one (the in-window receiver clears the staged value so it isn't
    /// applied twice).
    func open(settingsTab: SettingsTab) {
        pendingSettingsTarget = .tab(settingsTab)
        open(tab: .settings)
        NotificationCenter.default.post(
            name: .selectSettingsTab,
            object: nil,
            userInfo: ["tab": settingsTab]
        )
    }

    /// Open Settings and jump to a section (command-palette navigation).
    /// Same staging + post pattern as `open(settingsTab:)`.
    func open(settingsSection tab: SettingsTab, label: String) {
        pendingSettingsTarget = .section(tab: tab, label: label)
        open(tab: .settings)
        NotificationCenter.default.post(
            name: .selectSettingsSection,
            object: nil,
            userInfo: ["tab": tab, "label": label]
        )
    }

    /// Open the window's Dictionary destination and jump to one of its
    /// sections (command-palette navigation). Same staging + post pattern as
    /// `open(settingsSection:label:)`.
    func open(dictionarySection label: String) {
        pendingDictionarySection = label
        open(tab: .dictionary)
        NotificationCenter.default.post(
            name: .selectSettingsSection,
            object: nil,
            userInfo: ["tab": SettingsTab.vocabulary, "label": label]
        )
    }

    func open(tab: SottoWindowTab, activate: Bool = true) {
        // Navigating anywhere but Settings invalidates a staged Settings
        // target — otherwise it survives and fires on the next manual visit.
        if tab != .settings {
            pendingSettingsTarget = nil
        }
        if tab != .dictionary {
            pendingDictionarySection = nil
        }
        pendingTab = tab
        let shouldActivate = activate && !AppRuntimeMode.isHeadlessTest
        if shouldActivate {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        opener?(Self.windowID)
        if shouldActivate {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    /// Pure mapping from a deep-link destination string to its routing action.
    /// Returns nil for unknown destinations. Side-effect free → unit-testable
    /// and guarantees every `DeepLinkTarget` kind is covered.
    static func routingAction(for destination: String) -> DeepLinkRoutingAction? {
        switch DeepLinkRouter.target(for: destination) {
        case .settings(let tab):    return .openSettings(tab)
        case .sottoWindow(let tab): return .openSottoWindow(tab)
        case .onboarding:           return .presentOnboarding
        case nil:                   return nil
        }
    }

    /// App-level deep-link routing. Lives on the always-alive coordinator (not
    /// inside the on-demand Sotto window), so Settings/History/etc. links are
    /// never dropped when the window is closed.
    @MainActor
    func route(destination: String) {
        switch Self.routingAction(for: destination) {
        case .openSettings(let tab):
            // Models graduated to a first-class window destination (2026-07
            // revamp) — the legacy settings-tab deep link lands there instead.
            if tab == .models {
                open(tab: .models)
                return
            }
            open(settingsTab: tab)
        case .openSottoWindow(let tab):
            open(tab: tab)
        case .presentOnboarding:
            OnboardingWindowController.shared.present()
        case nil:
            break
        }
    }
}
