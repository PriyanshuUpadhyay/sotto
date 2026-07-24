import XCTest
import SwiftUI
@testable import Sotto

@MainActor
final class SettingsModelsTabTests: XCTestCase {

    func test_modelsTab_isConstructible() {
        _ = ModelsTab()
    }

    func test_modelsTab_conformsToView() {
        XCTAssertTrue((ModelsTab() as Any) is any View)
    }

    // MARK: - Anchor: descriptor == rendered set
    //
    // The body renders `ForEach(ModelsTab.renderedSections)` through an
    // EXHAUSTIVE `view(for:)` switch. `renderedSections == ModelsTabSection
    // .allCases`, so the rendered composition IS the descriptor by
    // construction: dropping a section requires removing its enum case (a
    // compile error in the exhaustive switch).

    func test_renderedSections_isExactlyAllCases() {
        XCTAssertEqual(
            ModelsTab.renderedSections,
            ModelsTab.ModelsTabSection.allCases,
            "body must render every descriptor case via ForEach(renderedSections)"
        )
    }

    func test_requiredSectionsPresent_transcriptionAndEnhancement() {
        let cases = Set(ModelsTab.ModelsTabSection.allCases)
        XCTAssertEqual(
            cases,
            [.transcription, .enhancement],
            "ModelsTab must surface exactly two flat sections; diff: \(cases.symmetricDifference([.transcription, .enhancement]))"
        )
    }

    // MARK: - Anchor (positive): transcription tiers
    // "Transcription models surface as Fast/Balanced/Best tiers; the existing
    //  TranscriptionModelManager download/select flow stays underneath."

    func test_transcriptionTier_isExhaustiveFastBalancedBest() {
        XCTAssertEqual(
            TranscriptionTier.allCases,
            [.fast, .realtime, .balanced, .best, .multilingual],
            "tiers must be exactly Fast/Realtime/Balanced/Best/Multilingual in order"
        )
    }

    /// The tier→modelId mapping must be TOTAL (every case yields a non-empty id)
    /// and CONCRETE (every id is a real model name the manager knows about).
    /// Dropping a tier breaks `allCases`; mapping a tier to an empty/bogus id
    /// fails here.
    func test_transcriptionTier_modelIdMapping_isTotalAndConcrete() {
        let knownNames = Set(TranscriptionModelMapper.availableModels().map { $0.name })
        XCTAssertFalse(knownNames.isEmpty, "bundled manifest must surface known model names")
        for tier in TranscriptionTier.allCases {
            XCTAssertFalse(tier.modelId.isEmpty, "tier \(tier) maps to an empty model id")
            XCTAssertTrue(
                knownNames.contains(tier.modelId),
                "tier \(tier) maps to unknown model id '\(tier.modelId)'; known: \(knownNames.sorted())"
            )
        }
    }

    /// Tier Map A — the exact in-app `TranscriptionModel.name` each tier selects.
    /// fast = Parakeet V2, realtime = Parakeet Unified, balanced = Large v3 Turbo Quantized, best = full
    /// Whisper Large v3 Turbo. NOTE: `best` uses the in-app `.name`
    /// `ggml-large-v3-turbo` (derived by TranscriptionModelMapper from the
    /// whisper manifest entry's source_url basename), which is the selectable
    /// name for manifest id `whisper-large-v3-turbo` — NOT the manifest id
    /// itself. This must FAIL if any tier maps to the wrong concrete id.
    func test_transcriptionTier_modelIdMapping_isExactlyTierMapA() {
        XCTAssertEqual(TranscriptionTier.fast.modelId, "parakeet-tdt-0.6b-v2",
                       "Fast must select Parakeet V2")
        XCTAssertEqual(TranscriptionTier.realtime.modelId, "parakeet-unified-0.6b",
                       "Realtime must select Parakeet Unified")
        XCTAssertEqual(TranscriptionTier.balanced.modelId, "ggml-large-v3-turbo-q5_0",
                       "Balanced must select Large v3 Turbo (Quantized)")
        XCTAssertEqual(TranscriptionTier.best.modelId, "ggml-large-v3-turbo",
                       "Best must select the full Whisper Large v3 Turbo (in-app name ggml-large-v3-turbo)")
        XCTAssertEqual(TranscriptionTier.multilingual.modelId, "parakeet-tdt-0.6b-v3",
                       "Multilingual must select Parakeet V3")
    }

    /// Distinct tiers must map to distinct models — a collapsed mapping would
    /// silently drop a tier's intent.
    func test_transcriptionTier_modelIds_areDistinct() {
        let ids = TranscriptionTier.allCases.map { $0.modelId }
        XCTAssertEqual(Set(ids).count, ids.count, "each tier must map to a distinct model id")
    }

    // MARK: - Anchor (negative): flat layout
    // "No segmented Enhancement/Transcriber control, no 'Other providers'
    //  accordion, no 'ACTIVE PROVIDER' label."
    //
    // Proven structurally via flags AND a source scan so the layout cannot
    // regress into the old accordion/segmented vocabulary.

    func test_modelsTab_isFlat_noAccordionNoModeSwitch() {
        XCTAssertFalse(ModelsTab.usesAccordion, "ModelsTab enhancement section must be flat (no provider accordion)")
        XCTAssertFalse(ModelsTab.usesModeSwitch, "ModelsTab must not segment Transcriber vs Enhancement")
    }

    func test_modelsTab_source_hasNoLegacyAccordionOrActiveProviderVocabulary() throws {
        let src = try modelsTabSource()
        XCTAssertFalse(src.contains("ACTIVE PROVIDER"),
                       "ModelsTab must not use the 'ACTIVE PROVIDER' label")
        XCTAssertFalse(src.contains("ActiveEnhancementProviderCard"),
                       "ModelsTab must not reuse the focal ACTIVE-PROVIDER card")
        XCTAssertFalse(src.contains("OtherEnhancementProvidersAccordion"),
                       "ModelsTab must not reuse the 'Other providers' accordion")
        XCTAssertFalse(src.contains("DisclosureGroup"),
                       "ModelsTab enhancement section must be flat (no DisclosureGroup accordion)")
        XCTAssertFalse(src.contains("Transcriber"),
                       "ModelsTab must not present a Transcriber/Enhancement segmented mode switch")
    }

    private func modelsTabSource() throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let worktreeRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = worktreeRoot
            .appendingPathComponent("Sotto/Views/Settings/Tabs/ModelsTab.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
