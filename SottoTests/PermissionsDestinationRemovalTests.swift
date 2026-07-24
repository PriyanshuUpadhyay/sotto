import XCTest
@testable import Sotto

final class PermissionsDestinationRemovalTests: XCTestCase {

    // The surviving permission surface carries the three real system permissions
    // (microphone / accessibility / screen recording) projected through the
    // read-only seam. There is no keyboard-shortcut-as-permission member to read.
    func test_permissionManager_exposesOnlyRealSystemPermissionStates() {
        let manager = PermissionManager()
        let rows = PermissionStatusRows(reading: manager)

        XCTAssertEqual(rows.microphone, manager.audioGranted)
        XCTAssertEqual(rows.accessibility, manager.accessibilityGranted)
        XCTAssertEqual(rows.screenRecording, manager.screenRecordingGranted)
    }

    // The legacy "Permissions" deep-link no longer opens a standalone Permissions
    // pane; it resolves to onboarding, where shortcut + permission setup now live.
    func test_permissionsDeepLink_resolvesToOnboarding_notADeadPane() {
        XCTAssertEqual(DeepLinkRouter.target(for: "Permissions"), .onboarding)
        XCTAssertEqual(SottoWindowCoordinator.routingAction(for: "Permissions"), .presentOnboarding)
    }

    // No deep-link destination addresses a standalone Permissions pane: every
    // known destination resolves to a settings tab, a Sotto window tab, or
    // onboarding — never a dead end.
    func test_knownDestinations_resolveToLivePanes_neverAPermissionsPane() {
        let known = [
            "Settings", "Models", "AI Models", "Enhancement",
            "History", "Permissions"
        ]
        for destination in known {
            guard let target = DeepLinkRouter.target(for: destination) else {
                XCTFail("\(destination) must resolve to a concrete target")
                continue
            }
            switch target {
            case .settings, .sottoWindow, .onboarding:
                break
            }
        }
    }
}
