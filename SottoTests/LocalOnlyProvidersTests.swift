import XCTest
@testable import Sotto

/// Locks the transcription provider surface to on-device only. The model
/// picker can never list a cloud provider because `ModelProvider.allCases`
/// is exactly {whisper, fluidAudio, nativeApple}.
final class LocalOnlyProvidersTests: XCTestCase {
    func testModelProviderIsExactlyOnDeviceSet() {
        XCTAssertEqual(
            Set(ModelProvider.allCases),
            Set([ModelProvider.whisper, .fluidAudio, .nativeApple])
        )
    }

    func testAIProviderIsExactlyOnDeviceSet() {
        // Enhancement collapsed to a single on-device path: Apple Foundation Models.
        XCTAssertEqual(Set(AIProvider.allCases), Set([AIProvider.foundationModels]))
    }
}
