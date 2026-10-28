import Foundation
import CoreML
import AVFoundation
import FluidAudio
import SwiftData
import os.log
import Darwin

extension FluidAudioTranscriptionService {
    // MARK: - Vocabulary rescoring

    /// `cbw 0` + `minSimilarity 0.7`. Measured on 241 real dictations
    /// (2026-10-05), the library defaults changed 40 transcripts, mostly wrongly
    /// ("code" → "Xcode", "getting" → "Gemini"); these settings changed none on
    /// the same vocabulary and fixed real misses once the terms were listed.
    /// Matches FluidAudio issue #967 (278 → 40 changed of 500, nearly all right).
    private static let rescoreCbw: Float = 0
    private static let rescoreMinSimilarity: Float = 0.7

    /// Map a thrown boosting error to the trace outcome (observability only).
    private static func boostingFallbackOutcome(for error: Error) -> TranscriptionTrace.BoostingTrace.Outcome {
        switch error {
        case VocabularyBoostingError.ctcModelMissing: return .ctcModelMissing
        case VocabularyBoostingError.emptyContext: return .fellBackToPlainDecode(reason: "empty context")
        default: return .fellBackToPlainDecode(reason: String(error.localizedDescription.prefix(60)))
        }
    }

    /// CTC-rescore a finished TDT decode against the custom vocabulary. Sets
    /// `lastBoosting`; returns nil (the caller keeps its text) on any failure.
    func rescore(_ result: ASRResult, samples: [Float], vocabulary: [String]) async
        -> VocabularyRescorer.RescoreOutput? {
        do {
            let ctcDir = CtcModels.defaultCacheDirectory(for: .ctc110m)
            guard CtcModels.modelsExist(at: ctcDir) else {
                // Never download on the transcribe hot path — prefetch for next time.
                Task.detached { _ = try? await CtcModels.downloadAndLoad(variant: .ctc110m) }
                throw VocabularyBoostingError.ctcModelMissing
            }
            guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else {
                throw VocabularyBoostingError.emptyContext
            }
            let ctcModels: CtcModels
            if let cached = ctcModelsCache {
                ctcModels = cached
            } else {
                ctcModels = try await CtcModels.load(from: ctcDir, variant: .ctc110m)
                ctcModelsCache = ctcModels
            }
            let context = try await vocabularyContext(for: vocabulary, ctcDir: ctcDir)
            guard !context.terms.isEmpty else { throw VocabularyBoostingError.emptyContext }

            let spotter = CtcKeywordSpotter(models: ctcModels, blankId: ctcModels.vocabulary.count)
            let spot = try await spotter.spotKeywordsWithLogProbs(
                audioSamples: samples, customVocabulary: context, minScore: nil)
            // Spotter rescue off: it swaps any ≤4-word span where the CTC spotter
            // hears a term and ignores `minSimilarity`. On a 39 s dictation
            // (2026-10-05) it made 18 swaps like "especially in" → "Gemini".
            let rescorer = try await VocabularyRescorer.create(
                spotter: spotter, vocabulary: context,
                config: .init(spotterRescueEnabled: false), ctcModelDirectory: ctcDir)
            let output = rescorer.ctcTokenRescore(
                transcript: result.text, tokenTimings: tokenTimings, logProbs: spot.logProbs,
                frameDuration: spot.frameDuration, cbw: Self.rescoreCbw,
                minSimilarity: Self.rescoreMinSimilarity)
            lastBoosting = .init(outcome: .engaged, termCount: vocabulary.count, terms: vocabulary)
            return output
        } catch {
            lastBoosting = .init(outcome: Self.boostingFallbackOutcome(for: error),
                                 termCount: vocabulary.count, terms: vocabulary)
            logger.notice("vocabulary rescoring unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The user's vocabulary minus the terms that over-fire (see
    /// `StreamingTranscriptRepair.boostableTerms`). Uses the system word list
    /// because NSSpellChecker accepts "laude" and "emini" and would drop Claude
    /// and Gemini. Scanned once per vocabulary, keeping only the hits.
    func boostableVocabulary() async -> [String] {
        let vocabulary = currentVocabulary()
        if let cached = boostableCache, cached.vocabulary == vocabulary { return cached.terms }
        let candidates = Set(vocabulary.map { String($0.trimmingCharacters(in: .whitespaces).dropFirst()).lowercased() })
        // A missing word list keeps every term (the length rule still applies).
        let words = (try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8)) ?? ""
        var hits = Set<String>()
        words.enumerateLines { line, _ in if candidates.contains(line) { hits.insert(line) } }
        let terms = StreamingTranscriptRepair.boostableTerms(vocabulary, isDictionaryWord: hits.contains)
        boostableCache = (vocabulary, terms)
        return terms
    }

    /// Build the CTC custom-vocabulary context (terms → CTC token ids), mirroring
    /// `AcousticVocabularyService`. The tokenizer is cached across dictations.
    private func vocabularyContext(for terms: [String], ctcDir: URL) async throws -> CustomVocabularyContext {
        let tokenizer: CtcTokenizer
        if let cached = ctcTokenizerCache {
            tokenizer = cached
        } else {
            tokenizer = try await CtcTokenizer.load(from: ctcDir)
            ctcTokenizerCache = tokenizer
        }
        let vocabTerms = terms.compactMap { text -> CustomVocabularyTerm? in
            let ids = tokenizer.encode(text)
            guard !ids.isEmpty else { return nil }
            return CustomVocabularyTerm(text: text, ctcTokenIds: ids)
        }
        return CustomVocabularyContext(terms: vocabTerms)
    }
}
