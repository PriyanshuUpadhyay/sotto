import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

@available(macOS 26.0, *)
extension AFMProvider {

    // MARK: - Availability

    /// Synchronous availability probe. Use from settings UI / `isAPIKeyValid`
    /// to decide whether to expose the provider. Throws a recoverable error
    /// if Apple Intelligence isn't ready; never crashes.
    nonisolated static func checkAvailability() throws {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                throw ProviderError.appleIntelligenceNotEnabled
            case .modelNotReady:
                throw ProviderError.modelNotReady
            case .deviceNotEligible:
                throw ProviderError.deviceNotEligible
            @unknown default:
                throw ProviderError.generationFailed("Unknown availability reason")
            }
        }
        #else
        throw ProviderError.frameworkUnavailable
        #endif
    }

    nonisolated static var isAvailable: Bool {
        do {
            try checkAvailability()
            return true
        } catch {
            return false
        }
    }

    /// Human-readable single-line description of why AFM is/isn't available,
    /// for the settings panel "Active path" indicator.
    nonisolated static func availabilityDescription() -> String {
        do {
            try checkAvailability()
            return "Apple Foundation Models"
        } catch let err as ProviderError {
            switch err {
            case .appleIntelligenceNotEnabled:
                return "Unavailable (Apple Intelligence not enabled)"
            case .modelNotReady:
                return "Unavailable (model still downloading)"
            case .deviceNotEligible:
                return "Unavailable (device not eligible)"
            case .frameworkUnavailable:
                return "Unavailable (FoundationModels framework missing)"
            default:
                return "Unavailable"
            }
        } catch {
            return "Unavailable"
        }
    }

    // MARK: - Helpers

    /// Heuristic guardrail-violation detector. Switches on the typed SDK
    /// error when present; otherwise falls back to localized-description
    /// substring matching to stay robust across SDK revisions.
    nonisolated static func isGuardrailViolation(_ error: Error) -> Bool {
        #if canImport(FoundationModels)
        if let genErr = error as? LanguageModelSession.GenerationError {
            switch genErr {
            case .guardrailViolation:
                return true
            default:
                return false
            }
        }
        #endif
        let desc = error.localizedDescription.lowercased()
        return desc.contains("guardrail") || desc.contains("safety")
    }
}
