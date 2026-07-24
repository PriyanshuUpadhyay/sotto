import XCTest
import SwiftUI
@testable import Sotto

@MainActor
final class SettingsRoutingTests: XCTestCase {

    private func capturedTab(routing destination: String) -> (pending: SottoWindowTab?, posted: SettingsTab?) {
        let coordinator = SottoWindowCoordinator.shared
        coordinator.pendingTab = nil
        // No-op opener so routing never depends on a real window, and the
        // headless test host's activation suppression keeps focus untouched.
        coordinator.registerOpener { _ in }

        var posted: SettingsTab?
        let token = NotificationCenter.default.addObserver(
            forName: .selectSettingsTab, object: nil, queue: nil
        ) { note in
            posted = note.userInfo?["tab"] as? SettingsTab
        }
        defer { NotificationCenter.default.removeObserver(token) }

        coordinator.route(destination: destination)
        return (coordinator.pendingTab, posted)
    }

    func test_routeSettings_stagesInWindowSettingsTab_andPostsGeneral() {
        let result = capturedTab(routing: "Settings")
        XCTAssertEqual(result.pending, .settings)
        XCTAssertEqual(result.posted, .general)
    }

    /// Models is a first-class window destination (2026-07 revamp): the legacy
    /// settings-tab deep link lands on the window's Models tab, no tab post.
    func test_routeAIModels_stagesModelsWindowTab_andPostsNothing() {
        let result = capturedTab(routing: "AI Models")
        XCTAssertEqual(result.pending, .models)
        XCTAssertNil(result.posted)
    }

    /// The destination→action mapping is locked: route()'s side effect changed,
    /// not the routingAction mapping that DeepLinkRouterTests also covers.
    func test_routingAction_settings_mappingUnchanged() {
        XCTAssertEqual(SottoWindowCoordinator.routingAction(for: "Settings"), .openSettings(.general))
        XCTAssertEqual(SottoWindowCoordinator.routingAction(for: "AI Models"), .openSettings(.models))
    }
}
