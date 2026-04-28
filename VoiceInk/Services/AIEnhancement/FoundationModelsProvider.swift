import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// Forces the 3B foundation model to emit only the cleaned text field, without
/// conversational preamble/postamble. The framework parses the response into this
/// schema, so chatbot-style framing is impossible — only the `text` field comes back.
@available(macOS 26.0, *)
@Generable
struct CleanedDictation {
    @Guide(description: "The transcript rewritten with proper grammar, capitalization, and punctuation. Plain text only. No markdown, no quotes, no explanation, no preamble like 'Here is...' — just the cleaned text itself.")
    var text: String
}
#endif

/// On-device LLM provider using Apple's Foundation Models framework.
/// Available on macOS 26+ with Apple Intelligence enabled. All state is actor-isolated.
/// The dispatch site (AIEnhancementService.makeRequest) is responsible for guarding the
/// `if #available(macOS 26.0, *)` and host-side passthrough fallback on error.
@available(macOS 26.0, *)
actor FoundationModelsProvider {

    enum ProviderError: Error, LocalizedError {
        case appleIntelligenceNotEnabled
        case modelNotReady
        case deviceNotEligible
        case frameworkUnavailable
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is not enabled. Enable it in System Settings → Apple Intelligence & Siri."
            case .modelNotReady:
                return "Apple Foundation Models are still downloading or warming up. Try again in a moment."
            case .deviceNotEligible:
                return "This device does not support Apple Foundation Models."
            case .frameworkUnavailable:
                return "FoundationModels framework is not available in this build."
            case .generationFailed(let why):
                return "Foundation Models generation failed: \(why)"
            }
        }
    }

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FoundationModelsProvider")

    init() {}

    /// Synchronous availability probe. Use from settings UI / `isAPIKeyValid` to decide
    /// whether to expose the provider. Throws a recoverable error if Apple Intelligence
    /// isn't ready; never crashes.
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

    /// Match the de-facto contract used by LocalCLIService.enhance(systemPrompt:userPrompt:).
    /// Returns the cleaned-up text; the dispatch site applies AIEnhancementOutputFilter.
    func enhance(systemPrompt: String, userPrompt: String) async throws -> String {
        #if canImport(FoundationModels)
        try Task.checkCancellation()
        try Self.checkAvailability()

        logger.notice("🍎 enhance: instr=\(systemPrompt.count, privacy: .public) chars, user=\(userPrompt.count, privacy: .public) chars")

        // Fresh session per call: the system prompt embeds dynamic context (clipboard,
        // screen capture, custom vocabulary) that changes per dictation, so reuse would
        // cross-contaminate. Sessions are cheap.
        let session = LanguageModelSession(instructions: systemPrompt)

        do {
            let start = Date()
            let response = try await session.respond(
                to: userPrompt,
                generating: CleanedDictation.self
            )
            let elapsed = Date().timeIntervalSince(start)
            logger.notice("🍎 respond(generating:) returned in \(elapsed, privacy: .public)s, text=\(response.content.text.count, privacy: .public) chars")
            try Task.checkCancellation()
            return response.content.text
        } catch is CancellationError {
            logger.notice("🍎 cancelled")
            throw CancellationError()
        } catch {
            logger.error("🍎 generate failed: \(error.localizedDescription, privacy: .public) | \(String(describing: error), privacy: .public)")
            throw ProviderError.generationFailed(error.localizedDescription)
        }
        #else
        throw ProviderError.frameworkUnavailable
        #endif
    }
}
