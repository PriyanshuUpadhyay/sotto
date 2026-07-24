import Foundation
import FluidAudio
import os

/// Acoustic confirmation of custom-vocabulary terms via FluidAudio's CTC keyword
/// spotter. Given the dictation audio and the user's vocab terms, returns the
/// subset the CTC model confirms were actually spoken. Used to gate the phonetic
/// corrector (only rewrite toward a term the audio supports) and to safely unlock
/// homophone rewrites that are otherwise too risky.
///
/// Opt-in: the ~110M CTC model is downloaded only when the user enables the
/// "Acoustic vocabulary boosting" setting. Fail-open everywhere — any load/run
/// failure yields an empty set so the corrector falls back to its OOV-only path
/// and a dictation never blocks on a download.
actor AcousticVocabularyService {
    static let shared = AcousticVocabularyService()
    private init() {}

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "AcousticVocabulary")

    /// Per-term keep threshold; also passed to the spotter as its `minScore`.
    private let scoreThreshold: Float = ContextBiasingConstants.defaultMinSpotterScore

    private var models: CtcModels?
    private var tokenizer: CtcTokenizer?
    private var spotter: CtcKeywordSpotter?

    /// Cached tokenized vocabulary, keyed by the term list so repeated dictations
    /// with an unchanged glossary skip re-tokenization.
    private var cachedTermsKey: String?
    private var cachedContext: CustomVocabularyContext?

    /// Download (first time) + load the CTC model. Call when the user enables the
    /// setting so the cost is paid up front, not on the first dictation.
    func prepareModel() async throws {
        guard spotter == nil else { return }
        let models = try await CtcModels.downloadAndLoad(variant: .ctc110m)
        let tokenizer = try await CtcTokenizer.load()
        self.models = models
        self.tokenizer = tokenizer
        self.spotter = CtcKeywordSpotter(models: models)
        logger.notice("CTC acoustic model loaded")
    }

    /// Terms (lowercased) the spotter confirms were spoken in the recording at
    /// `audioURL`. Empty on any failure or when the model isn't loaded — never
    /// throws, never blocks a dictation.
    func confirmedTerms(at audioURL: URL, terms: [String]) async -> Set<String> {
        let details = await confirmedTermsDetailed(at: audioURL, terms: terms)
        return confirmedTermSet(from: details)
    }

    /// Terms (lowercased) the spotter confirms were spoken in `audioSamples`.
    /// Empty on any failure or when the model isn't loaded — never throws.
    func confirmedTerms(in audioSamples: [Float], terms: [String]) async -> Set<String> {
        let details = await confirmedTermsDetailed(in: audioSamples, terms: terms)
        return confirmedTermSet(from: details)
    }

    /// Per-term detections including below-threshold (rejected) ones, for the
    /// pipeline trace. `kept == true` means the term cleared the threshold —
    /// terms the spotter never detected at all simply don't appear here.
    func confirmedTermsDetailed(at audioURL: URL, terms: [String]) async -> [TranscriptionTrace.AcousticDetection] {
        guard !terms.isEmpty, let samples = Self.readPCM16Samples(from: audioURL) else { return [] }
        return await confirmedTermsDetailed(in: samples, terms: terms)
    }

    /// In-samples variant of `confirmedTermsDetailed`. Empty on any failure.
    func confirmedTermsDetailed(in audioSamples: [Float], terms: [String]) async -> [TranscriptionTrace.AcousticDetection] {
        guard !terms.isEmpty, !audioSamples.isEmpty else { return [] }
        guard let spotter, let tokenizer else { return [] }
        do {
            let context = vocabularyContext(for: terms, tokenizer: tokenizer)
            guard !context.terms.isEmpty else { return [] }
            let result = try await spotter.spotKeywordsWithLogProbs(
                audioSamples: audioSamples,
                customVocabulary: context,
                minScore: scoreThreshold
            )
            let detections = result.detections.map { (term: $0.term.text, score: $0.score) }
            return acousticDetails(detections: detections, scoreThreshold: scoreThreshold)
        } catch {
            logger.notice("acoustic confirmation failed; falling back to OOV-only: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func vocabularyContext(for terms: [String], tokenizer: CtcTokenizer) -> CustomVocabularyContext {
        let key = terms.joined(separator: "\u{1F}")
        if key == cachedTermsKey, let cachedContext { return cachedContext }
        let vocabTerms = terms.compactMap { text -> CustomVocabularyTerm? in
            let ids = tokenizer.encode(text)
            guard !ids.isEmpty else { return nil }
            return CustomVocabularyTerm(text: text, ctcTokenIds: ids)
        }
        let context = CustomVocabularyContext(terms: vocabTerms)
        cachedTermsKey = key
        cachedContext = context
        return context
    }

    /// Parse a 16kHz mono PCM16 WAV (the app's recording format) into normalized
    /// `[Float]`. Mirrors `FluidAudioTranscriptionService.readAudioSamples`.
    /// Returns nil (fail-open) on any read error.
    private static func readPCM16Samples(from url: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: url), data.count > 44 else { return nil }
        return stride(from: 44, to: data.count - 1, by: 2).map { i in
            data[i..<i + 2].withUnsafeBytes {
                let short = Int16(littleEndian: $0.load(as: Int16.self))
                return max(-1.0, min(Float(short) / 32767.0, 1.0))
            }
        }
    }
}

/// Best detection per term (lowercased), each flagged kept if its score clears
/// the threshold. Pure so the score→keep decision is testable without the CTC
/// model. Includes rejected terms so the pipeline trace can show near-misses.
func acousticDetails(detections: [(term: String, score: Float)], scoreThreshold: Float) -> [TranscriptionTrace.AcousticDetection] {
    var best: [String: Float] = [:]
    for d in detections {
        let key = d.term.lowercased()
        if let existing = best[key] { best[key] = max(existing, d.score) } else { best[key] = d.score }
    }
    return best.map { TranscriptionTrace.AcousticDetection(term: $0.key, score: $0.value, kept: $0.value >= scoreThreshold) }
}

/// Keep terms whose best detection score clears the threshold; returns them
/// lowercased. Derives from `acousticDetails` so there's one score→keep rule.
func confirmedTermSet(detections: [(term: String, score: Float)], scoreThreshold: Float) -> Set<String> {
    confirmedTermSet(from: acousticDetails(detections: detections, scoreThreshold: scoreThreshold))
}

/// The kept subset of a detection list, lowercased.
func confirmedTermSet(from details: [TranscriptionTrace.AcousticDetection]) -> Set<String> {
    Set(details.filter { $0.kept }.map { $0.term })
}
