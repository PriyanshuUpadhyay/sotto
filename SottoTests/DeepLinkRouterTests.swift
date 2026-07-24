import XCTest
@testable import Sotto

final class DeepLinkRouterTests: XCTestCase {

    // Every legacy destination string maps to a concrete window/tab target;
    // none falls through to a no-op (nil). This is the f04 router contract.

    func test_settings_mapsToGeneralSettingsTab() {
        XCTAssertEqual(DeepLinkRouter.target(for: "Settings"), .settings(.general))
    }

    func test_models_aiModels_enhancement_collapseToModelsSettingsTab() {
        XCTAssertEqual(DeepLinkRouter.target(for: "Models"), .settings(.models))
        XCTAssertEqual(DeepLinkRouter.target(for: "AI Models"), .settings(.models))
        XCTAssertEqual(DeepLinkRouter.target(for: "Enhancement"), .settings(.models))
    }

    func test_permissions_mapsToOnboarding() {
        XCTAssertEqual(DeepLinkRouter.target(for: "Permissions"), .onboarding)
    }

    func test_history_mapsToSottoHistoryTab() {
        XCTAssertEqual(DeepLinkRouter.target(for: "History"), .sottoWindow(.history))
    }

    /// No dead-end: each legacy destination poster resolves non-nil.
    func test_allKnownLegacyDestinations_resolveNonNil() {
        let known = [
            "Settings", "Models", "AI Models", "Enhancement",
            "History", "Permissions"
        ]
        for destination in known {
            XCTAssertNotNil(
                DeepLinkRouter.target(for: destination),
                "Known destination \"\(destination)\" must resolve to a concrete target, not dead-end"
            )
        }
    }

    func test_unknownDestination_returnsNil() {
        XCTAssertNil(DeepLinkRouter.target(for: "DefinitelyNotADestination"))
    }

    // MARK: - App-level routing action coverage

    // The coordinator's pure `routingAction(for:)` maps each target kind to the
    // concrete action the always-alive app-level router takes. This guarantees
    // routing covers every DeepLinkTarget kind (.settings / .sottoWindow /
    // .onboarding) and that unknown destinations stay no-ops.

    func test_routingAction_settings_opensSettingsTab() {
        XCTAssertEqual(SottoWindowCoordinator.routingAction(for: "Settings"), .openSettings(.general))
        XCTAssertEqual(SottoWindowCoordinator.routingAction(for: "AI Models"), .openSettings(.models))
    }

    func test_routingAction_sottoWindow_opensSottoTab() {
        XCTAssertEqual(SottoWindowCoordinator.routingAction(for: "History"), .openSottoWindow(.history))
    }

    func test_routingAction_permissions_presentsOnboarding() {
        XCTAssertEqual(SottoWindowCoordinator.routingAction(for: "Permissions"), .presentOnboarding)
    }

    func test_routingAction_unknownDestination_returnsNil() {
        XCTAssertNil(SottoWindowCoordinator.routingAction(for: "DefinitelyNotADestination"))
    }
}
