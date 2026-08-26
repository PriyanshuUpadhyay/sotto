import XCTest
@testable import Sotto

/// Covers `features/mac_platform_conformance.feature` scenarios 01, 02 and 04.
/// Scenario 03 (VoiceOver labels) lives in `A11yContractTests`.
@MainActor
final class MacPlatformConformanceTests: XCTestCase {

    // MARK: - 01 — one documented minimum macOS version

    func test_minimumMacOS_is26() {
        XCTAssertEqual(PlatformSupport.minimumMacOS.majorVersion, 26)
        XCTAssertEqual(PlatformSupport.minimumMacOS.minorVersion, 0)
    }

    /// The string the docs and the build setting are checked against.
    func test_minimumMacOSDisplayString_matchesDeploymentTargetFormat() {
        XCTAssertEqual(PlatformSupport.minimumMacOSDisplayString, "26.0")
    }

    // MARK: - 02 — launch outcome per host version

    func test_supportedHost_opensMenuBarItem() {
        let outcome = PlatformSupport.launchOutcome(
            hostVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        )
        XCTAssertEqual(outcome, .opensMenuBarItem)
    }

    func test_olderHost_reportsUnsupportedMacOSVersion() {
        let outcome = PlatformSupport.launchOutcome(
            hostVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        XCTAssertEqual(outcome, .unsupportedMacOSVersion)
    }

    func test_newerHost_opensMenuBarItem() {
        let outcome = PlatformSupport.launchOutcome(
            hostVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 1, patchVersion: 0)
        )
        XCTAssertEqual(outcome, .opensMenuBarItem)
    }

    /// Boundary: one minor version below the minimum is still unsupported.
    func test_hostJustBelowMinimum_reportsUnsupportedMacOSVersion() {
        let outcome = PlatformSupport.launchOutcome(
            hostVersion: OperatingSystemVersion(majorVersion: 25, minorVersion: 9, patchVersion: 9)
        )
        XCTAssertEqual(outcome, .unsupportedMacOSVersion)
    }

    func test_unsupportedMessage_namesTheRequiredVersion() {
        XCTAssertTrue(
            PlatformSupport.unsupportedVersionMessage.contains(PlatformSupport.minimumMacOSDisplayString),
            "the message must tell the user which macOS version Sotto needs"
        )
    }

    // MARK: - 04 — appearance preference wins over the system appearance

    func test_followSystem_defersToSystemAppearance() {
        XCTAssertNil(AppearanceChoice.system.colorScheme,
                     "a nil colorScheme is what defers to the system appearance")
    }

    func test_lightPreference_rendersLight() {
        XCTAssertEqual(AppearanceChoice.light.colorScheme, .light)
    }

    func test_darkPreference_rendersDark() {
        XCTAssertEqual(AppearanceChoice.dark.colorScheme, .dark)
    }

    func test_appearanceStore_persistsChoice() {
        let suite = "MacPlatformConformanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let store = AppearanceStore(defaults: defaults)
        XCTAssertEqual(store.choice, .system, "no stored preference means follow system")

        store.choice = .light
        XCTAssertEqual(AppearanceStore(defaults: defaults).choice, .light,
                       "a chosen appearance must survive a relaunch")
    }
}
