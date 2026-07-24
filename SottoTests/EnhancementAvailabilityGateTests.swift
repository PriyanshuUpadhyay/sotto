import Testing
import Foundation
import SwiftData
@testable import Sotto

struct AIServiceAvailabilityGateTests {
    @Test func refreshAPIKeyValidityPicksUpLiveAvailabilityChange() {
        var available = false
        let service = AIService(availabilityProvider: { available })
        service.refreshAPIKeyValidity()
        #expect(service.isAPIKeyValid == false)

        available = true
        service.refreshAPIKeyValidity()
        #expect(service.isAPIKeyValid == true)
    }
}

@MainActor
struct EnhancementServiceAvailabilityGateTests {
    private func container() -> ModelContainer {
        let schema = Schema([EnhancementEditRecord.self])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [cfg])
    }

    /// A transient `.modelNotReady` at launch must recover once AFM becomes
    /// ready, with no restart / no new AIEnhancementService instance.
    @Test func isConfiguredRecoversLiveWithoutRestart() {
        var available = false
        let aiService = AIService(availabilityProvider: { available })
        aiService.refreshAPIKeyValidity()

        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: ModelContext(container()))
        #expect(enhancementService.isConfigured == false)

        available = true
        #expect(enhancementService.isConfigured == true)
    }

    @Test func isConfiguredReflectsAvailabilityGoingAwayLive() {
        var available = true
        let aiService = AIService(availabilityProvider: { available })
        aiService.refreshAPIKeyValidity()

        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: ModelContext(container()))
        #expect(enhancementService.isConfigured == true)

        available = false
        #expect(enhancementService.isConfigured == false)
    }
}
