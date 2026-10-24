import Testing
import Foundation
import SwiftData
@testable import Sotto

struct AIServiceAvailabilityGateTests {
    @Test(arguments: AIProvider.allCases)
    func refreshAPIKeyValidityPicksUpLiveAvailabilityChange(provider: AIProvider) {
        var available = false
        let service = AIService(
            providerSelection: { provider },
            availabilityProvider: provider == .foundationModels ? { available } : { !available },
            ggufAvailabilityProvider: provider == .localGGUF ? { available } : { !available }
        )
        service.refreshAPIKeyValidity()
        #expect(service.isAPIKeyValid == false)

        available = true
        service.refreshAPIKeyValidity()
        #expect(service.isAPIKeyValid == true)
    }

    /// The injected selection, not real defaults, decides the provider, and a
    /// refresh moves both `selectedProvider` and `isAPIKeyValid` to the new one.
    @Test func refreshAPIKeyValidityFollowsInjectedProviderChange() {
        var selection = AIProvider.foundationModels
        let service = AIService(
            providerSelection: { selection },
            availabilityProvider: { true },
            ggufAvailabilityProvider: { false }
        )
        #expect(service.selectedProvider == .foundationModels)
        #expect(service.isAPIKeyValid == true)

        selection = .localGGUF
        service.refreshAPIKeyValidity()
        #expect(service.selectedProvider == .localGGUF)
        #expect(service.isAPIKeyValid == false)
    }
}

@MainActor
struct EnhancementServiceAvailabilityGateTests {
    private func container() -> ModelContainer {
        let schema = Schema([EnhancementEditRecord.self])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [cfg])
    }

    /// A transient unavailability at launch must recover once the provider becomes
    /// ready, with no restart / no new AIEnhancementService instance.
    @Test(arguments: AIProvider.allCases)
    func isConfiguredRecoversLiveWithoutRestart(provider: AIProvider) {
        var available = false
        let aiService = AIService(
            providerSelection: { provider },
            availabilityProvider: provider == .foundationModels ? { available } : { !available },
            ggufAvailabilityProvider: provider == .localGGUF ? { available } : { !available }
        )
        aiService.refreshAPIKeyValidity()

        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: ModelContext(container()))
        #expect(enhancementService.isConfigured == false)

        available = true
        #expect(enhancementService.isConfigured == true)
    }

    @Test(arguments: AIProvider.allCases)
    func isConfiguredReflectsAvailabilityGoingAwayLive(provider: AIProvider) {
        var available = true
        let aiService = AIService(
            providerSelection: { provider },
            availabilityProvider: provider == .foundationModels ? { available } : { !available },
            ggufAvailabilityProvider: provider == .localGGUF ? { available } : { !available }
        )
        aiService.refreshAPIKeyValidity()

        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: ModelContext(container()))
        #expect(enhancementService.isConfigured == true)

        available = false
        #expect(enhancementService.isConfigured == false)
    }
}
