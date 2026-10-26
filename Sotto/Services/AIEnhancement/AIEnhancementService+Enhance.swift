import Foundation
import os

extension AIEnhancementService {
    /// One deadline wraps the whole call (first pass, network retries, hardened
    /// retry) so per-attempt timeouts inside `performEnhance` never compound.
    func enhance(_ text: String) async throws -> (String, TimeInterval, String?) {
        return try await withEnhancementDeadline(seconds: enhancementTimeoutSeconds) {
            try await self.performEnhance(text, isImport: false)
        }
    }

    /// File-import re-enhance entry point (`AudioTranscriptionService.
    /// retranscribeAudio`). Deliberately isolated from every piece of shared,
    /// mutable per-dictation state: never reads or bumps `dictationGeneration`
    /// / `dictationSnapshot` (an import can run WHILE a real recording is
    /// live — touching either would clear that recording's pending captures,
    /// warm, and snapshot out from under it), and never reads the captured
    /// selected-text/clipboard/screen stores either (those belong to a real
    /// recording, not the file being re-enhanced). Active app and custom
    /// vocabulary are always a live read. Never attempts AFM warm-session
    /// reuse: passes generation `-1`, which can never equal a real
    /// `dictationGeneration` (only ever increments from 0), so
    /// `AFMProvider`'s generation-match reuse check always misses and a fresh
    /// session is built every time.
    func enhanceImported(_ text: String) async throws -> (String, TimeInterval, String?) {
        return try await withEnhancementDeadline(seconds: enhancementTimeoutSeconds) {
            try await self.performEnhance(text, isImport: true)
        }
    }

    private func performEnhance(_ text: String, isImport: Bool) async throws -> (String, TimeInterval, String?) {
        let startTime = Date()
        let promptName = PredefinedPrompts.defaultPrompt.title

        // The record-start snapshot (`captureDictationSnapshot`) IF one exists
        // for the current generation, not a fresh live read: the prompt's
        // register directive and the post-LLM mechanics pass below must see
        // the SAME category the record-start AFM warm used, even if the user
        // switches focus while the (multi-second) enhancement is in flight —
        // otherwise the warm key (which depends on category) never matches.
        // Imports (`isImport`) skip this entirely and always read live — they
        // never have, and must never read, a recording's snapshot.
        let activeApp = isImport ? activeAppForContext : resolvedActiveApp
        let category = AppCategory.from(bundleID: activeApp?.bundleID)
        // `enhance(_:)` is a fixed external entry point (called by
        // TranscriptionPipeline) with no generation parameter to receive, so
        // this reads whatever's CURRENT rather than "the generation THIS
        // dictation's record-start used" — correct for the normal sequential
        // case (no new recording starts before this call runs), but NOT a
        // hard guarantee under hands-free (`runPipeline` can let a new
        // recording start while a prior utterance's enhance is still
        // in-flight). `AFMProvider`'s tag check still only ever grants reuse
        // when this happens to match a still-live matching warm; the worst
        // case on a hands-free race is a missed reuse (falls back to a fresh
        // session), never a wrong/contaminated one. Imports use `-1` instead —
        // see `enhanceImported`'s doc comment.
        let generation = isImport ? -1 : dictationGeneration
        let customVocabulary = isImport
            ? customVocabularyService.getCustomVocabulary(from: modelContext)
            : resolvedCustomVocabulary

        let firstPass = try await makeRequestWithRetry(text: text, activeApp: activeApp, generation: generation, customVocabulary: customVocabulary, isImport: isImport)
        var result = firstPass
        var outcome: EnhancementGuardOutcome = .notRun

        // Repair guard: the cleanup prompt must clean, not answer. Empty input
        // has nothing to judge. On a suspect first pass, retry once with the
        // hardened prompt; if still suspect, fall back to a model-free
        // deterministic cleanup.
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let vocabulary = customVocabularyWords()
            if EnhancementSanityCheck.detect(raw: text, output: firstPass, vocabulary: vocabulary).isSuspect {
                logger.notice("🦾 guard: first pass suspect — retrying with hardened prompt")
                let hardenedRetry: String?
                do {
                    hardenedRetry = try await makeRequest(text: text, hardened: true, generation: generation)
                } catch is CancellationError {
                    // Deadline/caller cancellation must unwind here, not be
                    // absorbed into a "successful" deterministic fallback below.
                    throw CancellationError()
                } catch {
                    hardenedRetry = nil
                }
                if let retry = hardenedRetry,
                   EnhancementSanityCheck.detect(raw: text, output: retry, vocabulary: vocabulary).isClean {
                    logger.notice("🦾 guard: hardened retry recovered")
                    result = retry
                    outcome = .retryRecovered
                } else {
                    logger.notice("🦾 guard: retry still suspect — deterministic fallback")
                    result = EnhancementSanityCheck.deterministicCleanup(text)
                    outcome = .deterministicFallback
                    await MainActor.run { self.lastEnhancementModelUsed = "deterministic-cleanup" }
                }
            } else {
                outcome = .none
            }
        }

        // Deterministic per-category punctuation mechanics — applied to whichever
        // text won above (first pass, hardened retry, or deterministic fallback),
        // so a mechanic like the personal-chat trailing-period drop lands uniformly.
        result = category.applyMechanics(to: result)
        if UserDefaults.standard.bool(forKey: ConciseCleanup.userDefaultsKey) {
            result = ConciseCleanup.apply(result)
        }

        await MainActor.run {
            self.lastRawEnhancement = firstPass
            self.lastGuardOutcome = outcome
        }
        let duration = Date().timeIntervalSince(startTime)
        return (result, duration, promptName)
    }

    /// Lowercased custom-vocabulary words for the repair guard's grounding
    /// check — parsed from the SAME "Important Vocabulary: a, b, c" string
    /// the prompt's `<CUSTOM_VOCABULARY>` section is built from, not a second
    /// store.
    private func customVocabularyWords() -> Set<String> {
        let formatted = customVocabularyService.getCustomVocabulary(from: modelContext)
        guard let range = formatted.range(of: ": ") else { return [] }
        var words = Set<String>()
        for term in formatted[range.upperBound...].split(separator: ",") {
            words.formUnion(term.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        }
        return words
    }
}
