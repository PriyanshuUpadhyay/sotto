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
    /// .selectSettingsSection notifications are lossy when SottoWindowView
    /// isn't mounted yet, so `open(settingsTab:)` / `open(settingsSection:)`
    /// stage here and the window consumes it on mount. One value — latest wins,
    /// no contradictory state.
    var pendingSettingsTarget: PendingSettingsTarget?

    private var opener: ((String) -> Void)?

    private init() {}

    func registerOpener(_ opener: @escaping (String) -> Void) {
        self.opener = opener
    }

    /// Open the sidebar row a Settings routing key names. Stages the target for
    /// a not-yet-mounted window AND posts the notification for a mounted one
    /// (the window clears the staged value so it isn't applied twice).
    func open(settingsTab: SettingsTab) {
        pendingSettingsTarget = .tab(settingsTab)
        open(tab: SottoWindowTab(settingsTab: settingsTab))
        NotificationCenter.default.post(
            name: .selectSettingsTab,
            object: nil,
            userInfo: ["tab": settingsTab]
        )
    }

    /// Open a sidebar row and jump to one of its sections (command-palette
    /// navigation). Same staging + post pattern as `open(settingsTab:)`.
    func open(settingsSection tab: SettingsTab, label: String) {
        pendingSettingsTarget = .section(tab: tab, label: label)
        open(tab: SottoWindowTab(settingsTab: tab))
        NotificationCenter.default.post(
            name: .selectSettingsSection,
            object: nil,
            userInfo: ["tab": tab, "label": label]
        )
    }

    func open(tab: SottoWindowTab, activate: Bool = true) {
        // Navigating to a different row invalidates a staged target —
        // otherwise it survives and fires on the next manual visit.
        if let staged = pendingSettingsTarget, SottoWindowTab(settingsTab: staged.tab) != tab {
            pendingSettingsTarget = nil
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
