import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

@available(macOS 26.0, *)
extension AFMProvider {

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
}
