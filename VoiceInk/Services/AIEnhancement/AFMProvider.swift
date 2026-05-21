import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device LLM provider using Apple's Foundation Models framework (AFM).
/// Available on macOS 26+ with Apple Intelligence enabled.
///
/// W11.B — promoted to the **primary** local-enhance path; MLX becomes the
/// fallback for users whose machine doesn't have AFM available (Intel,
/// Apple Intelligence disabled, or model still downloading). The dispatch
/// site (AIEnhancementService.makeRequest) handles routing + safety-filter
/// fallback to MLX.
///
/// All state is actor-isolated. Per-call timing is captured and emitted to
/// `EnhancementTimingLogger.shared.record(promptMode: .afm, …)` matching the
/// MLXProvider telemetry shape so AFM rows show up alongside MLX rows in the
/// CSV.
@available(macOS 26.0, *)
actor AFMProvider {

    enum ProviderError: Error, LocalizedError {
        case appleIntelligenceNotEnabled
        case modelNotReady
        case deviceNotEligible
        case frameworkUnavailable
        case generationFailed(String)
        /// W11.B — sentinel for AFM safety-filter (guardrail) refusals so the
        /// orchestrator can transparently fall back to MLX without surfacing
        /// the refusal as a user-visible error. Other generation errors keep
        /// propagating via `.generationFailed`.
        case safetyRefusal(String)

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
            case .safetyRefusal(let why):
                return "Apple Foundation Models refused this prompt (safety filter): \(why)"
            }
        }
    }

    nonisolated static let logger = Logger(subsystem: OSLogSubsystems.app, category: "AFMProvider")

    init() {}

    // MARK: - Availability

    /// Synchronous availability probe. Use from settings UI / `isAPIKeyValid`
    /// to decide whether to expose the provider, and from the routing layer
    /// to pick AFM-vs-MLX. Throws a recoverable error if Apple Intelligence
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

    /// Human-readable single-line description of why AFM is/isn't available,
    /// for the settings panel "Active path" indicator.
    nonisolated static func availabilityDescription() -> String {
        do {
            try checkAvailability()
            return "Apple Foundation Models"
        } catch let err as ProviderError {
            switch err {
            case .appleIntelligenceNotEnabled:
                return "MLX (Apple Intelligence not enabled)"
            case .modelNotReady:
                return "MLX (AFM model still downloading)"
            case .deviceNotEligible:
                return "MLX (device not eligible for AFM)"
            case .frameworkUnavailable:
                return "MLX (FoundationModels framework unavailable)"
            default:
                return "MLX (AFM unavailable)"
            }
        } catch {
            return "MLX (AFM unavailable)"
        }
    }

    // MARK: - Enhance (with timing telemetry)

    /// Match the de-facto contract used by `LocalCLIService.enhance(systemPrompt:userPrompt:)`
    /// and `MLXProvider.enhance(...)`. Returns the cleaned-up text; the dispatch
    /// site applies `AIEnhancementOutputFilter` + `stripPreamble`.
    ///
    /// Captures per-call prep / ttft / gen / total timing and records a
    /// `promptMode=afm` row in `EnhancementTimingLogger` from every outcome
    /// branch (success / cancelled / error). Safety-filter refusals throw
    /// `ProviderError.safetyRefusal` so the orchestrator can fall back to MLX.
    func enhance(systemPrompt: String, userPrompt: String) async throws -> String {
        #if canImport(FoundationModels)
        try Task.checkCancellation()
        try Self.checkAvailability()

        let startedAt = Date()
        let inputChars = userPrompt.count
        var prepSeconds: TimeInterval? = nil
        var ttftSeconds: TimeInterval? = nil
        var genSeconds: TimeInterval? = nil
        var outputChars: Int = 0

        func record(_ outcome: EnhancementTimingLogger.Outcome) async {
            let total = Date().timeIntervalSince(startedAt)
            await EnhancementTimingLogger.shared.record(
                modelId: "apple-on-device",
                promptMode: .afm,
                inputChars: inputChars,
                outputChars: outputChars,
                prepSeconds: prepSeconds,
                ttftSeconds: ttftSeconds,
                genSeconds: genSeconds,
                totalSeconds: total,
                startedAt: startedAt,
                outcome: outcome
            )
        }

        Self.logger.notice("🦾 afm: instr=\(systemPrompt.count, privacy: .public)c user=\(userPrompt.count, privacy: .public)c")

        // Fresh session per call: the system prompt embeds dynamic context
        // (clipboard, screen capture, custom vocabulary) that changes per
        // dictation, so reuse would cross-contaminate. Sessions are cheap.
        let prepStart = Date()
        let session = LanguageModelSession(instructions: systemPrompt)
        prepSeconds = Date().timeIntervalSince(prepStart)

        do {
            let genStart = Date()
            var output = ""
            var firstChunkAt: TimeInterval? = nil

            // Streaming path so we can capture TTFT. Each emitted snapshot is
            // a cumulative slice (Apple's `ResponseStream<String>.Snapshot`
            // contract); `.content` is the full text generated so far.
            let stream = session.streamResponse(to: userPrompt)
            for try await snapshot in stream {
                if Task.isCancelled { break }
                if firstChunkAt == nil {
                    firstChunkAt = Date().timeIntervalSince(genStart)
                }
                output = snapshot.content
            }
            try Task.checkCancellation()
            let genElapsed = Date().timeIntervalSince(genStart)
            let ttft = firstChunkAt ?? genElapsed
            ttftSeconds = ttft
            genSeconds = genElapsed
            outputChars = output.count

            Self.logger.notice("🦾 afm: prep=\(prepSeconds ?? 0, format: .fixed(precision: 2), privacy: .public)s ttft=\(ttft, format: .fixed(precision: 2), privacy: .public)s gen=\(genElapsed, format: .fixed(precision: 2), privacy: .public)s input=\(inputChars, privacy: .public)c output=\(output.count, privacy: .public)c")

            await record(.success)
            return output
        } catch is CancellationError {
            await record(.cancelled)
            Self.logger.notice("🦾 afm: cancelled")
            throw CancellationError()
        } catch {
            // Detect AFM safety-filter (guardrail) refusal so the dispatcher
            // can fall back to MLX. SDK exposes this as
            // `LanguageModelSession.GenerationError.guardrailViolation` on
            // macOS 26; fallback to localized-description matching keeps us
            // forward-compatible across SDK revisions.
            let isSafety = Self.isGuardrailViolation(error)
            if isSafety {
                await record(.error)
                Self.logger.notice("🦾 afm: refused (safety filter) — \(error.localizedDescription, privacy: .public)")
                throw ProviderError.safetyRefusal(error.localizedDescription)
            }
            await record(.error)
            Self.logger.error("🦾 afm: generate failed: \(error.localizedDescription, privacy: .public) | \(String(describing: error), privacy: .public)")
            throw ProviderError.generationFailed(error.localizedDescription)
        }
        #else
        throw ProviderError.frameworkUnavailable
        #endif
    }

    // MARK: - Prewarm

    /// W11.B prewarm hook. Mirrors `MLXProvider.warm(source:)` so the
    /// `ModelPrewarmService` can fire on the same triggers (app launch,
    /// wake, recording start). Calls `LanguageModelSession.prewarm()` to
    /// trigger asset paging without running an enhancement.
    func warm(source: String) async {
        #if canImport(FoundationModels)
        guard Self.isAvailable else {
            Self.logger.notice("🦾 afm: prewarm skipped — AFM unavailable (source=\(source, privacy: .public))")
            return
        }
        let start = Date()
        // `LanguageModelSession.prewarm()` is a static-side hint on macOS 26;
        // wire via a throwaway session whose lifetime is the prewarm call.
        let session = LanguageModelSession(instructions: "")
        session.prewarm()
        let elapsed = Date().timeIntervalSince(start)
        Self.logger.notice("🦾 afm: prewarm fired source=\(source, privacy: .public) in \(elapsed, format: .fixed(precision: 2), privacy: .public)s")
        #else
        Self.logger.notice("🦾 afm: prewarm no-op (framework unavailable, source=\(source, privacy: .public))")
        #endif
    }

    /// Drop any cached state. Symmetric with `MLXProvider.reset()`. AFM
    /// sessions are cheap and not pooled at this layer, so this is a no-op
    /// today — kept for API parity + future-proofing.
    func reset() {
        Self.logger.notice("🦾 afm: reset (no-op)")
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
