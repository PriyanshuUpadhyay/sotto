import XCTest
@testable import Sotto

final class TranscriptionTierMappingTests: XCTestCase {

    // MARK: - Anchor (positive)
    // "Each tier maps to exactly one concrete model id and back; the mapping is
    //  total over the tier set."

    func test_forwardMapping_isTotal_everyTierHasNonEmptyModelId() {
        for tier in TranscriptionTier.allCases {
            XCTAssertFalse(tier.modelId.isEmpty, "tier \(tier) maps to an empty model id")
        }
    }

    func test_roundTrip_modelIdResolvesBackToSameTier() {
        for tier in TranscriptionTier.allCases {
            XCTAssertEqual(
                TranscriptionTier(modelId: tier.modelId),
                tier,
                "modelId '\(tier.modelId)' must resolve back to tier \(tier)"
            )
        }
    }

    func test_reverseMapping_isNilForUnknownModelId() {
        XCTAssertNil(TranscriptionTier(modelId: "not-a-real-model"))
        XCTAssertNil(TranscriptionTier(modelId: ""))
    }

    func test_reverseMapping_discriminatesBetweenTiers() {
        XCTAssertEqual(TranscriptionTier(modelId: "parakeet-tdt-0.6b-v2"), .fast)
        XCTAssertEqual(TranscriptionTier(modelId: "parakeet-unified-0.6b"), .realtime)
        XCTAssertEqual(TranscriptionTier(modelId: "ggml-large-v3-turbo-q5_0"), .balanced)
        XCTAssertEqual(TranscriptionTier(modelId: "ggml-large-v3-turbo"), .best)
        XCTAssertEqual(TranscriptionTier(modelId: "parakeet-tdt-0.6b-v3"), .multilingual)
        XCTAssertNotEqual(TranscriptionTier(modelId: "parakeet-tdt-0.6b-v2"), .best)
    }

    // Tier Map A — user-approved concrete ids (in-app TranscriptionModel.name).
    func test_forwardMapping_isExactlyTierMapA() {
        XCTAssertEqual(TranscriptionTier.fast.modelId, "parakeet-tdt-0.6b-v2")
        XCTAssertEqual(TranscriptionTier.realtime.modelId, "parakeet-unified-0.6b")
        XCTAssertEqual(TranscriptionTier.balanced.modelId, "ggml-large-v3-turbo-q5_0")
        XCTAssertEqual(TranscriptionTier.best.modelId, "ggml-large-v3-turbo")
        XCTAssertEqual(TranscriptionTier.multilingual.modelId, "parakeet-tdt-0.6b-v3")
    }

    // Each tier's modelId must be a real model name the manager surfaces, so a
    // tier selection always hands a manager-known model to setDefaultTranscriptionModel.
    func test_everyTierModelId_isAManagerKnownModelName() {
        let knownNames = Set(TranscriptionModelMapper.availableModels().map { $0.name })
        XCTAssertFalse(knownNames.isEmpty, "bundled manifest must surface known model names")
        for tier in TranscriptionTier.allCases {
            XCTAssertTrue(
                knownNames.contains(tier.modelId),
                "tier \(tier) maps to unknown model id '\(tier.modelId)'; known: \(knownNames.sorted())"
            )
        }
    }
}
