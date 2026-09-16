import XCTest
import Foundation
import SwiftData
@testable import Sotto

final class EnhancementProviderTests: XCTestCase {
    func test_allProvidersAndRawValues() {
        XCTAssertEqual(AIProvider.allCases, [.foundationModels, .localGGUF])
        XCTAssertEqual(AIProvider.foundationModels.rawValue, "Apple Foundation Models")
        XCTAssertEqual(AIProvider.localGGUF.rawValue, "Local model (GGUF)")
    }

    func test_preferenceSet_modelNotDownloaded_resolvesFoundationModels() {
        let defaults = isolatedDefaults()
        defaults.set(AIProvider.localGGUF.rawValue, forKey: "EnhancementProvider")
        XCTAssertEqual(
            AIProvider.resolved(defaults: defaults, isDownloaded: { _ in false }),
            .foundationModels
        )
    }

    func test_preferenceSet_modelDownloaded_resolvesLocalGGUF() {
        let defaults = isolatedDefaults()
        defaults.set(AIProvider.localGGUF.rawValue, forKey: "EnhancementProvider")
        XCTAssertEqual(
            AIProvider.resolved(defaults: defaults, isDownloaded: { _ in true }),
            .localGGUF
        )
    }

    func test_decodeUnknownRawValue_fallsBackToFoundationModels() throws {
        let decoded = try JSONDecoder().decode(
            AIProvider.self,
            from: Data(#""unknown-provider""#.utf8)
        )
        XCTAssertEqual(decoded, .foundationModels)
    }

    func test_decodeKnownRawValues() throws {
        let local = try JSONDecoder().decode(
            AIProvider.self,
            from: Data(#""Local model (GGUF)""#.utf8)
        )
        let afm = try JSONDecoder().decode(
            AIProvider.self,
            from: Data(#""Apple Foundation Models""#.utf8)
        )
        XCTAssertEqual(local, .localGGUF)
        XCTAssertEqual(afm, .foundationModels)
    }

    @MainActor
    func test_ggufProviderError_fallsBackToAFM_andMarksFallback() async throws {
        let defaults = isolatedDefaults()
        defaults.set(AIProvider.localGGUF.rawValue, forKey: "EnhancementProvider")
        AIProvider.defaultsOverride = defaults
        AIProvider.isDownloadedOverride = { _ in true }
        defer {
            AIProvider.defaultsOverride = nil
            AIProvider.isDownloadedOverride = nil
        }

        let aiService = AIService(
            availabilityProvider: { true },
            ggufAvailabilityProvider: { true }
        )
        aiService.ggufEnhanceHandler = { _, _, _, _, _ in
            throw GGUFProvider.ProviderError.generationFailed("simulated failure")
        }
        aiService.afmEnhanceHandler = { _, _, _, _, _ in "Test transcript." }

        let schema = Schema([EnhancementEditRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let service = AIEnhancementService(
            aiService: aiService,
            modelContext: ModelContext(container)
        )

        let (output, _, _) = try await service.enhance("test transcript")
        XCTAssertEqual(service.lastEnhancementModelUsed, "apple-on-device (fallback)")
        XCTAssertFalse(output.isEmpty)
    }

    func test_noPreference_resolvesFoundationModels() {
        XCTAssertEqual(
            AIProvider.resolved(defaults: isolatedDefaults(), isDownloaded: { _ in true }),
            .foundationModels
        )
    }

    func test_modelIdentifier_namesSelectedGGUFModel() {
        let defaults = UserDefaults.standard
        let oldSlug = defaults.object(forKey: "EnhancementGGUFModelSlug")
        defer {
            if let oldSlug {
                defaults.set(oldSlug, forKey: "EnhancementGGUFModelSlug")
            } else {
                defaults.removeObject(forKey: "EnhancementGGUFModelSlug")
            }
        }

        GGUFModelRegistry.selectedSlug = "s1-mini"
        XCTAssertEqual(AIProvider.foundationModels.modelIdentifier, "apple-on-device")
        XCTAssertEqual(AIProvider.localGGUF.modelIdentifier, "gguf-s1-mini")

        GGUFModelRegistry.selectedSlug = "speakoflow-mini"
        XCTAssertEqual(AIProvider.localGGUF.modelIdentifier, "gguf-speakoflow-mini")
    }

    func test_availabilityDescription_namesOnlyAFM() {
        XCTAssertFalse(AFMProvider.availabilityDescription().contains("GGUF"))
    }

    @MainActor
    func test_ggufDownloadManager_pauseResumeCancel() async throws {
        let slug = "speakoflow-mini"
        let manager = GGUFDownloadManager.shared
        manager.cancel(slug)

        guard let finalURL = GGUFModelRegistry.fileURL(slug: slug) else {
            XCTFail("Missing fileURL for slug")
            return
        }
        let partURL = finalURL.appendingPathExtension("part")
        XCTAssertFalse(FileManager.default.fileExists(atPath: partURL.path))

        // Start download
        manager.start(slug)
        XCTAssertEqual(manager.state(for: slug), .downloading)

        // Wait until some bytes are received (> 0 progress)
        let startTime = Date()
        var gotProgress = false
        while Date().timeIntervalSince(startTime) < 15.0 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if manager.progress(for: slug) > 0 {
                gotProgress = true
                break
            }
        }

        guard gotProgress else {
            manager.cancel(slug)
            throw XCTSkip("Network download did not start in time or offline")
        }

        // Pause download
        manager.pause(slug)
        XCTAssertEqual(manager.state(for: slug), .paused)

        // Wait a little to ensure pause settles
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(manager.state(for: slug), .paused)

        // Resume download
        manager.resume(slug)
        XCTAssertEqual(manager.state(for: slug), .downloading)

        // Let it download briefly
        try await Task.sleep(nanoseconds: 500_000_000)

        // Cancel download
        manager.cancel(slug)
        XCTAssertEqual(manager.state(for: slug), .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partURL.path), "Partial file must be removed on cancel")
    }
}
