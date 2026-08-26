import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device LLM provider using Apple's Foundation Models framework (AFM).
/// Available on macOS 26+ with Apple Intelligence enabled.
///
/// The only local-enhance path. When AFM is unavailable (Intel, Apple
/// Intelligence disabled, or model still downloading) enhancement is reported
/// as unavailable rather than routed elsewhere.
///
/// All state is actor-isolated. Per-call timing is captured and emitted to
/// `EnhancementTimingLogger.shared.record(promptMode: .afm, …)`.
@available(macOS 26.0, *)
actor AFMProvider {

    enum ProviderError: Error, LocalizedError {
        case appleIntelligenceNotEnabled
        case modelNotReady
        case deviceNotEligible
        case frameworkUnavailable
        case generationFailed(String)
        /// Sentinel for AFM safety-filter (guardrail) refusals so the
        /// orchestrator can surface them as `EnhancementError.safetyRefusal`
        /// rather than a generic failure. Other generation errors keep
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

    // One-shot warmed session. Prewarmed at recording start with the prospective
    // system prompt; consumed by the NEXT `enhance(...)` iff its instructions
    // match, then discarded. This preserves the "fresh session per dictation"
    // invariant (no cross-dictation transcript contamination) while letting a
    // matching enhance reuse the already-prefilled instruction prefix — cutting
    // time-to-first-token, the dominant per-enhance cost.
    #if canImport(FoundationModels)
    private var warmedInstructions: String?
    private var warmedSession: LanguageModelSession?
    /// Dictation generation the warm belongs to (`AIEnhancementService`'s
    /// counter, threaded through `warm(...)`). Consumption in `enhance(...)`
    /// requires an EXACT match on top of the instruction-string match — a
    /// warm that lands after its own dictation ended (cancelled, or simply
    /// slow) can never be claimed by whatever dictation is current by then,
    /// even if that dictation's instructions happen to be identical (e.g.
    /// two consecutive dictations in the same app).
    private var warmedGeneration: Int?
    /// When the warm slot was stashed. Reported as `warmAgeSeconds` on a
    /// reusing enhance — a TTFT that rises with this age means AFM is letting
    /// the prefilled prefix decay, which is a different problem than prefill
    /// simply being expensive.
    private var warmedAt: Date?
    #endif

    /// Chains the fire-and-forget telemetry writes in `enhance(...)` so they
    /// land in submission order. Unstructured `Task {}` jobs have no FIFO
    /// guarantee even though the logger actor serializes each individual
    /// write — `EnhancementTimingLogger` derives `gapSinceLastSeconds` from
    /// processing order, so an out-of-order write would corrupt that gap.
    /// Each new job awaits the previous one's completion before recording,
    /// still off the response path (the response path only creates the Task,
    /// never awaits it).
    #if canImport(FoundationModels)
    private var lastTelemetryTask: Task<Void, Never>?
    #endif

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

    // MARK: - Enhance (with timing telemetry)

    /// Returns the cleaned-up text; the dispatch site
    /// (`AIEnhancementService.makeRequest`) applies `AIEnhancementOutputFilter`
    /// + `stripPreamble`. This is the only enhance path — there is no fallback
    /// provider behind it.
    ///
    /// Captures per-call prep / ttft / gen / total timing and enqueues a
    /// `promptMode=afm` row to `EnhancementTimingLogger` from every outcome
    /// branch (success / cancelled / safetyRefusal / error) — fire-and-forget,
    /// so the response path never awaits the logger actor's disk I/O. Safety-
    /// filter refusals record `.safetyRefusal` (keeping the refusal rate
    /// measurable from the timings CSV) and throw `ProviderError.safetyRefusal`,
    /// which the dispatch site surfaces as an enhancement error — the dictation
    /// goes out un-enhanced.
    func enhance(
        systemPrompt: String,
        userPrompt: String,
        transcriptChars: Int,
        callKind: EnhancementTimingLogger.CallKind,
        generation: Int
    ) async throws -> String {
        #if canImport(FoundationModels)
        try Task.checkCancellation()
        try Self.checkAvailability()

        let startedAt = Date()
        var prepSeconds: TimeInterval? = nil
        var ttftSeconds: TimeInterval? = nil
        var genSeconds: TimeInterval? = nil
        var outputChars: Int = 0

        // Fire-and-forget: the response path returns/throws immediately after
        // enqueuing, it never awaits the logger actor's (synchronous, disk-I/O)
        // write. `outputChars`/`prepSeconds`/`ttftSeconds`/`genSeconds` are
        // passed in rather than captured so the enqueued Task closure holds
        // immutable snapshots, not references to this function's `var`s.
        // Chained through `lastTelemetryTask` so concurrent enhance() calls'
        // writes still land in submission order (unstructured Tasks alone
        // have no FIFO guarantee) — each job awaits the previous one first.
        func record(
            _ outcome: EnhancementTimingLogger.Outcome,
            outputChars: Int,
            prepSeconds: TimeInterval?,
            ttftSeconds: TimeInterval?,
            genSeconds: TimeInterval?,
            sessionReused: Bool,
            warmAgeSeconds: TimeInterval?
        ) {
            let total = Date().timeIntervalSince(startedAt)
            lastTelemetryTask = Task { [prev = lastTelemetryTask] in
                await prev?.value
                await EnhancementTimingLogger.shared.record(
                    modelId: "apple-on-device",
                    promptMode: .afm,
                    transcriptChars: transcriptChars,
                    promptChars: systemPrompt.count + userPrompt.count,
                    callKind: callKind,
                    warmAgeSeconds: warmAgeSeconds,
                    outputChars: outputChars,
                    prepSeconds: prepSeconds,
                    ttftSeconds: ttftSeconds,
                    genSeconds: genSeconds,
                    totalSeconds: total,
                    startedAt: startedAt,
                    outcome: outcome,
                    sessionReused: sessionReused
                )
            }
        }

        Self.logger.notice("🦾 afm: instr=\(systemPrompt.count, privacy: .public)c user=\(userPrompt.count, privacy: .public)c")

        // Reuse the recording-start prewarmed session iff its instructions match
        // this call's system prompt — the prefix is already prefilled, so ttft
        // drops. Otherwise build fresh. For a real dictation (generation >= 0)
        // the warmed slot is cleared immediately either way: a session is
        // reused for exactly ONE dictation, never across dictations (whose
        // dynamic context — clipboard, screen capture, custom vocabulary —
        // would otherwise cross-contaminate). Sessions are cheap to build, so
        // the fresh-fallback path is the unchanged baseline. An import/history
        // re-enhance (generation `-1`, see `AIEnhancementService`) can never
        // match the warm slot and must NOT clear it — that would discard the
        // live dictation's prefilled session out from under it.
        let prepStart = Date()
        let session: LanguageModelSession
        let reusedWarm: Bool
        let warmAge: TimeInterval?
        if let warmed = warmedSession, warmedInstructions == systemPrompt, warmedGeneration == generation {
            session = warmed
            reusedWarm = true
            warmAge = warmedAt.map { prepStart.timeIntervalSince($0) }
        } else {
            session = LanguageModelSession(instructions: systemPrompt)
            reusedWarm = false
            warmAge = nil
        }
        if generation >= 0 {
            warmedSession = nil
            warmedInstructions = nil
            warmedGeneration = nil
            warmedAt = nil
        }
        prepSeconds = Date().timeIntervalSince(prepStart)

        do {
            let genStart = Date()
            var output = ""
            var firstChunkAt: TimeInterval? = nil

            // Greedy sampling: cleanup is a deterministic transform, so the
            // default random sampling only adds run-to-run variance. No
            // `maximumResponseTokens` — the stream exposes no finish reason, so
            // a capped response is indistinguishable from a complete one and
            // would be recorded as a silent `.success` truncation. Wall-clock is
            // already bounded by the per-call enhancement deadline.
            let options = GenerationOptions(sampling: .greedy)
            // Streaming path so we can capture TTFT. Each emitted snapshot is
            // a cumulative slice (Apple's `ResponseStream<String>.Snapshot`
            // contract); `.content` is the full text generated so far.
            let stream = session.streamResponse(to: userPrompt, options: options)
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

            Self.logger.notice("🦾 afm: prep=\(prepSeconds ?? 0, format: .fixed(precision: 2), privacy: .public)s ttft=\(ttft, format: .fixed(precision: 2), privacy: .public)s gen=\(genElapsed, format: .fixed(precision: 2), privacy: .public)s transcript=\(transcriptChars, privacy: .public)c output=\(output.count, privacy: .public)c warm=\(reusedWarm, privacy: .public)")

            record(.success, outputChars: outputChars, prepSeconds: prepSeconds, ttftSeconds: ttftSeconds, genSeconds: genSeconds, sessionReused: reusedWarm, warmAgeSeconds: warmAge)
            return output
        } catch is CancellationError {
            record(.cancelled, outputChars: outputChars, prepSeconds: prepSeconds, ttftSeconds: ttftSeconds, genSeconds: genSeconds, sessionReused: reusedWarm, warmAgeSeconds: warmAge)
            Self.logger.notice("🦾 afm: cancelled")
            throw CancellationError()
        } catch {
            // Detect AFM safety-filter (guardrail) refusal so the dispatcher
            // reports it as a refusal, not a failure. SDK exposes this as
            // `LanguageModelSession.GenerationError.guardrailViolation` on
            // macOS 26; fallback to localized-description matching keeps us
            // forward-compatible across SDK revisions.
            let isSafety = Self.isGuardrailViolation(error)
            if isSafety {
                record(.safetyRefusal, outputChars: outputChars, prepSeconds: prepSeconds, ttftSeconds: ttftSeconds, genSeconds: genSeconds, sessionReused: reusedWarm, warmAgeSeconds: warmAge)
                Self.logger.notice("🦾 afm: refused (safety filter) — \(error.localizedDescription, privacy: .public)")
                throw ProviderError.safetyRefusal(error.localizedDescription)
            }
            record(.error, outputChars: outputChars, prepSeconds: prepSeconds, ttftSeconds: ttftSeconds, genSeconds: genSeconds, sessionReused: reusedWarm, warmAgeSeconds: warmAge)
            Self.logger.error("🦾 afm: generate failed: \(error.localizedDescription, privacy: .public) | \(String(describing: error), privacy: .public)")
            throw ProviderError.generationFailed(error.localizedDescription)
        }
        #else
        throw ProviderError.frameworkUnavailable
        #endif
    }

    // MARK: - Prewarm

    /// Prewarm hook, so the
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

    /// Prewarm a session built with the prospective enhance *instructions* and
    /// stash it for one-shot reuse by the next `enhance(...)`. Unlike
    /// `warm(source:)` (empty session — pages base weights only), this also
    /// primes the instruction prefix so a matching enhance skips that prefill,
    /// the dominant slice of AFM time-to-first-token. Fired at recording start
    /// where the prompt is already known.
    func warm(instructions: String, source: String, generation: Int) async {
        #if canImport(FoundationModels)
        guard Self.isAvailable else {
            Self.logger.notice("🦾 afm: prewarm(instr) skipped — AFM unavailable (source=\(source, privacy: .public))")
            return
        }
        let start = Date()
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        warmedSession = session
        warmedInstructions = instructions
        warmedGeneration = generation
        warmedAt = start
        let elapsed = Date().timeIntervalSince(start)
        Self.logger.notice("🦾 afm: prewarm(instr) fired source=\(source, privacy: .public) instr=\(instructions.count, privacy: .public)c in \(elapsed, format: .fixed(precision: 2), privacy: .public)s")
        #else
        Self.logger.notice("🦾 afm: prewarm(instr) no-op (framework unavailable, source=\(source, privacy: .public))")
        #endif
    }

    /// Drop any cached state — called unconditionally at the start of every
    /// NEW dictation (`AIEnhancementService.beginNewDictation`), on top of
    /// `enhance(...)`'s own generation-tagged consume check, so a warm from
    /// an ended dictation can never survive even briefly into whatever comes
    /// next.
    func reset() {
        #if canImport(FoundationModels)
        warmedSession = nil
        warmedInstructions = nil
        warmedGeneration = nil
        warmedAt = nil
        #endif
        Self.logger.notice("🦾 afm: reset")
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
