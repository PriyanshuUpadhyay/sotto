import Foundation
import CoreML
import AVFoundation
import FluidAudio
import SwiftData
import os.log
import Darwin

// `actor` (not a plain class): a single instance is now shared between the
// launch/wake prewarm (ModelPrewarmService → SottoEngine.warmUpTranscriptionModel)
// and real transcription (SottoEngine, off the main actor via Task.detached).
// Those callers race on `unifiedAsrManager`/`unifiedLoadingTask`, so actor
// isolation is required to make the check-then-set in the load dedup atomic.
// NOT `@MainActor` — the heavy `loadModels()` ANE compile must not run on the UI
// thread; it stays inside a Task and suspends, freeing the actor for reentrancy.
actor FluidAudioTranscriptionService: TranscriptionService {
    private var asrManager: AsrManager?
    private var unifiedAsrManager: UnifiedAsrManager?
    private var vadManager: VadManager?
    private var activeVersion: AsrModelVersion?
    private var cachedModels: AsrModels?
    private var loadingTask: (version: AsrModelVersion, task: Task<AsrModels, Error>)?
    // In-flight manager load (model file load + AsrManager.loadModels ANE
    // compile), keyed by version. Same dedup shape as `unifiedLoadingTask`:
    // only the initiator assigns `asrManager`; a same-version joiner awaits
    // this task then re-evaluates. A caller wanting a DIFFERENT version is a
    // version switch, not a join — it waits for this to settle (so it
    // doesn't race the initiator's cleanup) then proceeds as initiator.
    private var tdtLoadingTask: (version: AsrModelVersion, task: Task<AsrManager, Error>)?
    private var unifiedLoadingTask: Task<UnifiedAsrManager, Error>?
    // In-flight Cohere load, same dedup shape as `unifiedLoadingTask`.
    private var cohereLoadingTask: Task<CoherePipeline.LoadedModels, Error>?
    // Bumped at the start of every real (non-cached) family switch in
    // `ensureModelsLoaded`/`ensureUnifiedModelsLoaded`/`ensureCohereModels`.
    // Actor reentrancy at their `await`s lets a second family switch start
    // before the first finishes; whichever switch is about to assign its
    // freshly-loaded manager checks this counter first, and if a newer
    // switch has bumped it since, discards its own load and retries instead
    // of resurrecting a family a newer request already moved past. Cleanup
    // of other families stays unconditional (always correct/idempotent) —
    // only the final assignment is gated.
    private var familySwitchGeneration = 0
    // Cohere Transcribe (experimental, batch-only): loaded via CoherePipeline,
    // which has no manager type. Models + pipeline are cached across dictations.
    private var cohereModels: CoherePipeline.LoadedModels?
    private var coherePipeline: CoherePipeline?
    private let logger = Logger(subsystem: OSLogSubsystems.fluidAudio, category: "FluidAudioTranscriptionService")

    // MARK: - File-based vocabulary boosting (Milestone 2)
    //
    // The SwiftData container holding `VocabularyWord`, set once by the registry.
    // Used to fetch the live custom vocabulary off the main actor (a fresh
    // `ModelContext` is created on this actor's executor per fetch). Caches for
    // the CTC spotter model + tokenizer so repeated file dictations don't reload
    // them. All best-effort: any failure falls back to the plain decode.
    private var vocabularyContainer: ModelContainer?
    // KNOWN FOLLOW-UP (deferred): when a `.fast` user has acoustic boosting on,
    // this cache and `AcousticVocabularyService` each load their OWN CtcModels
    // (~2×110 MB resident + 2 CTC inferences/dictation). Acceptable for the
    // seed-sized vocabulary; the ideal fix is sharing one CtcModels instance
    // across the post-hoc spotter and this in-decoder rescorer.
    private var ctcModelsCache: CtcModels?
    private var ctcTokenizerCache: CtcTokenizer?

    private enum VocabularyBoostingError: Error { case ctcModelMissing, emptyContext }
    private var boostableCache: (vocabulary: [String], terms: [String])?

    /// Observability ONLY (no behavior): the M2 in-decoder rescore outcome for the
    /// most recent `transcribe(audioURL:model:)` call. Reset to nil at the top of
    /// every transcribe AND at streaming start (via `resetBoostingTrace`), so the
    /// pipeline's post-transcription read reflects this utterance only — a prior
    /// file decode's outcome can't bleed onto a realtime/streaming entry.
    private(set) var lastBoosting: TranscriptionTrace.BoostingTrace?

    /// Clear the boosting trace before a streaming (realtime/M1) run, which never
    /// calls `transcribe(audioURL:model:)` and so would otherwise leave a stale
    /// file-decode outcome for the pipeline to misattribute.
    func resetBoostingTrace() { lastBoosting = nil }

    /// Inject the SwiftData container that owns `VocabularyWord`. Called by the
    /// registry at construction; the same actor instance serves every file path.
    func setVocabularyContainer(_ container: ModelContainer) {
        self.vocabularyContainer = container
    }

    private func currentVocabulary() -> [String] {
        guard let vocabularyContainer else { return [] }
        let context = ModelContext(vocabularyContainer)
        return (try? context.fetch(FetchDescriptor<VocabularyWord>()))?.map { $0.word } ?? []
    }

    /// Whether a heavy ASR model is already resident (warm). Drives the
    /// recorder's "warming up" vs "transcribing" label so a cold first
    /// dictation doesn't read as a freeze. Best-effort snapshot.
    var isModelLoaded: Bool {
        unifiedAsrManager != nil || asrManager != nil || cohereModels != nil
    }

    /// Whether `version`'s model FILES (not a loaded `AsrManager`) are cached.
    /// This is the real warm signal for `FluidAudioStreamingProvider`
    /// (agreement-based TDT streaming): it builds a fresh per-session
    /// `AsrManager` every time via `getOrLoadModels`, so `asrManager`/
    /// `isModelLoaded` residency here is irrelevant to its warmth.
    func isModelFilesCached(for version: AsrModelVersion) -> Bool {
        cachedModels?.version == version
    }

    /// Process physical memory footprint in MB (`task_vm_info.phys_footprint`),
    /// used to log residency around ASR family load/unload — see the
    /// dual-family-residency fixes in git history (277f39f, 2e192aa, 33ff097,
    /// 2149ea4). Internal (not private): the streaming providers share this
    /// same helper for their own load-complete footprint logs.
    static func residentFootprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint / 1024 / 1024)
    }

    private func version(for model: any TranscriptionModel) throws -> AsrModelVersion {
        guard let version = FluidAudioModelManager.knownAsrVersion(for: model.name) else {
            logger.error("Unsupported FluidAudio model id: \(model.name, privacy: .public)")
            throw SottoEngineError.unsupportedFluidAudioModel(model.name)
        }
        return version
    }

    private func ensureModelsLoaded(for version: AsrModelVersion) async throws {
        if asrManager != nil, activeVersion == version {
            return
        }

        if let (existingVersion, existingTask) = tdtLoadingTask {
            if existingVersion == version {
                _ = try await existingTask.value
                return try await ensureModelsLoaded(for: version)
            }
            _ = try? await existingTask.value
        }

        familySwitchGeneration += 1
        let myGeneration = familySwitchGeneration

        // Clean up existing manager but preserve cachedModels for reuse
        await unifiedAsrManager?.cleanup()
        unifiedAsrManager = nil
        await asrManager?.cleanup()
        asrManager = nil
        vadManager = nil
        activeVersion = nil
        cohereModels = nil
        coherePipeline = nil

        let task = Task { () throws -> AsrManager in
            let models = try await self.getOrLoadModels(for: version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        tdtLoadingTask = (version, task)

        do {
            let manager = try await task.value
            if tdtLoadingTask?.version == version {
                tdtLoadingTask = nil
            }

            // A newer family switch may have started (and already assigned a
            // different family) while we awaited above — discard and retry so
            // we don't resurrect TDT after it.
            guard familySwitchGeneration == myGeneration else {
                await manager.cleanup()
                return try await ensureModelsLoaded(for: version)
            }
            self.asrManager = manager
            self.activeVersion = version
            logger.notice("footprint after TDT load: \(Self.residentFootprintMB(), privacy: .public) MB")
        } catch {
            if tdtLoadingTask?.version == version {
                tdtLoadingTask = nil
            }
            throw error
        }
    }

    private func ensureUnifiedModelsLoaded() async throws {
        if unifiedAsrManager != nil {
            return
        }

        // Deduplicate concurrent loads: a second caller (e.g. a dictation
        // arriving while the launch prewarm is still loading) attaches to the
        // in-flight load instead of constructing a second `UnifiedAsrManager`
        // — two managers would each cold-load and serialize on the ANE,
        // doubling the time-to-first-transcript. Actor isolation makes the
        // `unifiedLoadingTask` check-then-set atomic; the awaits below run only
        // after the task is stored, so reentrancy is safe.
        //
        // Only the initiator (below) assigns `unifiedAsrManager` — a joiner
        // just waits for the in-flight load to settle, then re-evaluates
        // from the top. That covers the case where the initiator discards
        // its own load as stale (see `familySwitchGeneration`): the joiner
        // retries and either finds the fast path satisfied or starts a
        // fresh attempt itself.
        if let task = unifiedLoadingTask {
            _ = try await task.value
            return try await ensureUnifiedModelsLoaded()
        }

        familySwitchGeneration += 1
        let myGeneration = familySwitchGeneration

        await asrManager?.cleanup()
        asrManager = nil
        activeVersion = nil
        cohereModels = nil
        coherePipeline = nil

        let precision = FluidAudioModelManager.parakeetUnifiedPrecision
        let task = Task { () throws -> UnifiedAsrManager in
            let manager = UnifiedAsrManager(encoderPrecision: precision)
            try await manager.loadModels()
            return manager
        }
        unifiedLoadingTask = task

        do {
            let manager = try await task.value
            self.unifiedLoadingTask = nil

            // A newer family switch may have started (and already assigned
            // a different family) while we awaited the ANE compile above —
            // discard and retry so we don't resurrect Unified after it.
            guard familySwitchGeneration == myGeneration else {
                await manager.cleanup()
                return try await ensureUnifiedModelsLoaded()
            }
            self.unifiedAsrManager = manager
            logger.notice("footprint after Unified load: \(Self.residentFootprintMB(), privacy: .public) MB")
        } catch {
            self.unifiedLoadingTask = nil
            throw error
        }
    }

    // Returns cached models or loads from disk; deduplicates concurrent loads
    func getOrLoadModels(for version: AsrModelVersion) async throws -> AsrModels {
        if let cached = cachedModels, cached.version == version {
            return cached
        }

        // Deduplicate concurrent loads for the same version
        if let (existingVersion, existingTask) = loadingTask, existingVersion == version {
            return try await existingTask.value
        }

        let task = Task {
            try await AsrModels.loadFromCache(
                configuration: nil,
                version: version
            )
        }
        loadingTask = (version, task)

        do {
            let models = try await task.value
            self.cachedModels = models
            // Only clear if we're still the current loading task
            if loadingTask?.version == version {
                self.loadingTask = nil
            }
            return models
        } catch {
            // Only clear if we're still the current loading task
            if loadingTask?.version == version {
                self.loadingTask = nil
            }
            throw error
        }
    }

    func loadModel(for model: FluidAudioModel) async throws {
        if FluidAudioModelManager.isParakeetUnifiedModel(named: model.name) {
            try await ensureUnifiedModelsLoaded()
            return
        }
        if FluidAudioModelManager.isParakeetEouModel(named: model.name) {
            // EOU is streaming-only; its provider owns StreamingEouAsrManager
            // loading, so the batch prewarm path should not call knownAsrVersion.
            return
        }
        if FluidAudioModelManager.isNemotronStreamingModel(named: model.name) {
            // Nemotron streaming is streaming-only; its provider owns
            // StreamingNemotronAsrManager loading.
            return
        }
        if FluidAudioModelManager.isCohereModel(named: model.name) {
            _ = try await ensureCohereModels()
            return
        }
        try await ensureModelsLoaded(for: try version(for: model))
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        // Reset per-utterance boosting observability. Parakeet Unified leaves it
        // nil — boosting is structurally impossible there (no CTC head), so its
        // entries render no boosting line.
        lastBoosting = nil
        if FluidAudioModelManager.isParakeetUnifiedModel(named: model.name) {
            try await ensureUnifiedModelsLoaded()
            guard let unifiedAsrManager else {
                throw ASRError.notInitialized
            }
            let samples = try readAudioSamples(from: audioURL)
            let text = try await unifiedAsrManager.transcribe(samples)
            return TextNormalizer.shared.normalizeSentence(text)
        }
        if FluidAudioModelManager.isParakeetEouModel(named: model.name) {
            throw SottoEngineError.unsupportedFluidAudioModel(model.name)
        }
        if FluidAudioModelManager.isNemotronStreamingModel(named: model.name) {
            throw SottoEngineError.unsupportedFluidAudioModel(model.name)
        }
        if FluidAudioModelManager.isCohereModel(named: model.name) {
            let samples = try readAudioSamples(from: audioURL)
            let models = try await ensureCohereModels()
            let pipeline = coherePipeline ?? CoherePipeline()
            coherePipeline = pipeline
            let result = try await pipeline.transcribeLong(audio: samples, models: models)
            return TextNormalizer.shared.normalizeSentence(result.text)
        }

        let targetVersion = try version(for: model)
        try await ensureModelsLoaded(for: targetVersion)

        let audioSamples = try readAudioSamples(from: audioURL)

        let vocabulary = await boostableVocabulary()
        let attemptBoosting = FluidAudioVocabularyBoosting.shouldAttempt(modelName: model.name, vocabulary: vocabulary)
        if !attemptBoosting {
            // The gate said no (empty vocabulary or the acoustic-boosting policy is
            // off) — record it so the trace shows the gate evaluated.
            lastBoosting = .init(outcome: .notAttempted, termCount: vocabulary.count, terms: vocabulary)
        }

        guard let asrManager = asrManager else {
            throw ASRError.notInitialized
        }

        let durationSeconds = Double(audioSamples.count) / 16000.0
        let isVADEnabled = UserDefaults.standard.bool(forKey: "IsVADEnabled")

        var speechAudio = audioSamples
        if durationSeconds >= 20.0, isVADEnabled {
            let vadConfig = VadConfig(defaultThreshold: 0.7)
            if vadManager == nil {
                do {
                    vadManager = try await VadManager(config: vadConfig)
                } catch {
                    logger.notice("VAD init failed; falling back to full audio: \(error.localizedDescription, privacy: .public)")
                    vadManager = nil
                }
            }

            if let vadManager {
                do {
                    let segments = try await vadManager.segmentSpeechAudio(audioSamples)
                    speechAudio = segments.isEmpty ? audioSamples : segments.flatMap { $0 }
                } catch {
                    logger.notice("VAD segmentation failed; using full audio: \(error.localizedDescription, privacy: .public)")
                    speechAudio = audioSamples
                }
            }
        }

        // Pad with 1s of silence to capture final punctuation at sequence boundary
        let trailingSilenceSamples = 16_000
        let maxSingleChunkSamples = 240_000
        if speechAudio.count + trailingSilenceSamples <= maxSingleChunkSamples {
            speechAudio += [Float](repeating: 0, count: trailingSilenceSamples)
        }

        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(speechAudio, decoderState: &decoderState)

        var text = result.text
        if attemptBoosting, let rescored = await rescore(result, samples: speechAudio, vocabulary: vocabulary) {
            text = rescored.text
        }
        return TextNormalizer.shared.normalizeSentence(text)
    }

    /// Repairs a finished streaming (agreement-based TDT) transcript with one
    /// batch decode of the whole recording: appends trailing words streaming
    /// dropped, then applies the vocabulary rescorer's swaps when boosting is on.
    /// Streaming stays the base text (see `StreamingTranscriptRepair`). Returns
    /// `streaming` unchanged on any failure, so the repair never blocks a paste.
    func repairStreamingTranscript(_ streaming: String, audioURL: URL, model: any TranscriptionModel) async -> String {
        lastBoosting = nil
        do {
            let version = try version(for: model)
            try await ensureModelsLoaded(for: version)
            guard let asrManager else { return streaming }
            let samples = try readAudioSamples(from: audioURL)
            // Same 1 s trailing pad as the file path, for final punctuation.
            var padded = samples
            if padded.count + 16_000 <= 240_000 { padded += [Float](repeating: 0, count: 16_000) }
            var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
            let result = try await asrManager.transcribe(padded, decoderState: &decoderState)

            var text = StreamingTranscriptRepair.appendingDroppedTail(
                streaming: streaming, batch: TextNormalizer.shared.normalizeSentence(result.text))
            let vocabulary = await boostableVocabulary()
            if FluidAudioVocabularyBoosting.shouldAttempt(modelName: model.name, vocabulary: vocabulary) {
                if let rescored = await rescore(result, samples: samples, vocabulary: vocabulary) {
                    let swaps = rescored.replacements.compactMap { r -> (original: String, replacement: String)? in
                        guard r.shouldReplace, let word = r.replacementWord else { return nil }
                        return (r.originalWord, word)
                    }
                    text = StreamingTranscriptRepair.applyingSwaps(swaps, to: text)
                }
            } else {
                lastBoosting = .init(outcome: .notAttempted, termCount: vocabulary.count, terms: vocabulary)
            }
            return text
        } catch {
            logger.notice("streaming repair skipped: \(error.localizedDescription, privacy: .public)")
            return streaming
        }
    }

    /// Load (and cache) the Cohere CoreML encoder/decoder/vocab from the
    /// FluidAudio models cache. The bundle must already be on disk (downloaded
    /// via FluidAudioModelManager); loadModels throws if it isn't.
    private func ensureCohereModels() async throws -> CoherePipeline.LoadedModels {
        if let cached = cohereModels { return cached }

        // Deduplicate concurrent loads, same shape as `unifiedLoadingTask`:
        // only the initiator below assigns `cohereModels`; a joiner awaits
        // the in-flight load then re-evaluates from the top.
        if let task = cohereLoadingTask {
            _ = try await task.value
            return try await ensureCohereModels()
        }

        familySwitchGeneration += 1
        let myGeneration = familySwitchGeneration

        // Mutual lifecycle: release resident Parakeet managers so a model
        // switch doesn't leave both families' CoreML models loaded.
        await unifiedAsrManager?.cleanup()
        unifiedAsrManager = nil
        await asrManager?.cleanup()
        asrManager = nil
        vadManager = nil
        activeVersion = nil

        let dir = FluidAudioModelManager.cohereCacheDirectory()
        let task = Task { () throws -> CoherePipeline.LoadedModels in
            try await CoherePipeline.loadModels(
                encoderDir: dir, decoderDir: dir, vocabDir: dir)
        }
        cohereLoadingTask = task

        do {
            let loaded = try await task.value
            cohereLoadingTask = nil

            // A newer family switch may have started (and already assigned a
            // different family) while we awaited the load above — discard and
            // retry so we don't resurrect Cohere after it. `LoadedModels` needs
            // no explicit teardown (same as elsewhere in this file); dropping
            // `loaded` here is enough.
            guard familySwitchGeneration == myGeneration else {
                return try await ensureCohereModels()
            }
            cohereModels = loaded
            logger.notice("footprint after Cohere load: \(Self.residentFootprintMB(), privacy: .public) MB")
            return loaded
        } catch {
            cohereLoadingTask = nil
            throw error
        }
    }

    private func readAudioSamples(from url: URL) throws -> [Float] {
        do {
            let data = try Data(contentsOf: url)
            let headerSize = 44
            guard data.count > headerSize else {
                throw ASRError.invalidAudioData
            }

            let sampleCount = (data.count - headerSize) / 2
            var floats = [Float](repeating: 0, count: sampleCount)
            data.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
                guard let baseAddress = rawPtr.baseAddress else { return }
                for i in 0..<sampleCount {
                    let short = baseAddress.loadUnaligned(fromByteOffset: headerSize + i * 2, as: Int16.self)
                    floats[i] = max(-1.0, min(Float(Int16(littleEndian: short)) / 32767.0, 1.0))
                }
            }

            return floats
        } catch {
            throw ASRError.invalidAudioData
        }
    }

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
    private func rescore(_ result: ASRResult, samples: [Float], vocabulary: [String]) async
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
    private func boostableVocabulary() async -> [String] {
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

    // Releases ASR/VAD resources but preserves cached models for reuse
    func cleanup() async {
        // Invalidate any in-flight family load (see `familySwitchGeneration`):
        // its post-await guard will now fail, so it discards the manager it
        // just built instead of resurrecting it after this cleanup.
        familySwitchGeneration += 1

        if let manager = asrManager {
            await manager.cleanup()
        }
        if let manager = unifiedAsrManager {
            await manager.cleanup()
        }
        asrManager = nil
        unifiedAsrManager = nil
        unifiedLoadingTask = nil
        tdtLoadingTask = nil
        cohereLoadingTask = nil
        vadManager = nil
        activeVersion = nil
        cohereModels = nil
        coherePipeline = nil
        logger.notice("footprint after cleanup (in-flight loads may release later): \(Self.residentFootprintMB(), privacy: .public) MB")
    }

}
