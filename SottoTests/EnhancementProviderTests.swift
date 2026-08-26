import XCTest
import Foundation
@testable import Sotto

/// Covers `features/unreachable_code.feature` scenario 04: the hidden
/// `EnhancementProviderMLX` preference is inert now that the MLX path is gone,
/// so every enhancement runs on Apple Foundation Models.
final class EnhancementProviderTests: XCTestCase {

    func test_appleFoundationIsTheOnlyProvider() {
        XCTAssertEqual(AIProvider.allCases, [.foundationModels])
    }

    func test_hiddenMLXFlagOn_stillResolvesToAppleFoundation() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "EnhancementProviderMLX")
        XCTAssertEqual(AIProvider.resolved(defaults: defaults), .foundationModels)
    }

    func test_hiddenMLXFlagOff_resolvesToAppleFoundation() {
        XCTAssertEqual(AIProvider.resolved(defaults: isolatedDefaults()), .foundationModels)
    }

    /// The identifier recorded against a finished enhancement names the same
    /// provider the transcript actually ran on.
    func test_modelIdentifier_namesAppleOnDeviceModel() {
        XCTAssertEqual(AIProvider.foundationModels.modelIdentifier, "apple-on-device")
    }

    /// The availability line is shown to the user; it must never advertise a
    /// removed provider as the active path.
    func test_availabilityDescription_neverNamesMLX() {
        XCTAssertFalse(AFMProvider.availabilityDescription().contains("MLX"))
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "EnhancementProviderTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }
}
