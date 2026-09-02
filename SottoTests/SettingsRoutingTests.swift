import XCTest
import SwiftUI
@testable import Sotto

@MainActor
final class SettingsRoutingTests: XCTestCase {

    private func capturedTab(routing destination: String) -> (pending: SottoWindowTab?, posted: SettingsTab?) {
        let coordinator = SottoWindowCoordinator.shared
        coordinator.pendingTab = nil
        coordinator.pendingSettingsTarget = nil
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

    /// Settings is no longer a destination of its own — the deep link lands on
    /// the General sidebar row.
    func test_routeSettings_selectsGeneralSidebarRow() {
        let result = capturedTab(routing: "Settings")
        XCTAssertEqual(result.pending, .general)
        XCTAssertEqual(result.posted, .general)
    }

    /// The legacy settings-tab deep link for Models lands on the Models sidebar
    /// row, which now sits under the SETTINGS group header.
    func test_routeAIModels_selectsModelsSidebarRow() {
        let result = capturedTab(routing: "AI Models")
        XCTAssertEqual(result.pending, .models)
        XCTAssertEqual(result.posted, .models)
    }

    /// The destination→action mapping is locked: route()'s side effect changed,
    /// not the routingAction mapping that DeepLinkRouterTests also covers.
    func test_routingAction_settings_mappingUnchanged() {
        XCTAssertEqual(SottoWindowCoordinator.routingAction(for: "Settings"), .openSettings(.general))
        XCTAssertEqual(SottoWindowCoordinator.routingAction(for: "AI Models"), .openSettings(.models))
    }
}
