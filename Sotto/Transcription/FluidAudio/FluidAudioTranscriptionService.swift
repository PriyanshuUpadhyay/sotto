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

    private enum VocabularyBoostingError: Error { case ctcModelMissing, bufferFailed, emptyContext }

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

        // In-decoder vocabulary rescoring (FILE-BASED only). When the user's
        // custom vocabulary is non-empty and the CTC spotter model is already
        // resident on disk, run the decode through FluidAudio's
        // SlidingWindowAsrManager with `configureVocabularyBoosting`, which
        // applies `VocabularyRescorer.ctcTokenRescore` to confirmed tokens.
        // Best-effort: any failure (incl. a missing CTC model) falls through to
        // the plain TDT decode below, so transcription never breaks.
        let vocabulary = currentVocabulary()
        if FluidAudioVocabularyBoosting.shouldAttempt(modelName: model.name, vocabulary: vocabulary) {
            do {
                let boosted = try await transcribeWithVocabularyBoosting(
                    samples: audioSamples, version: targetVersion, vocabulary: vocabulary)
                logger.notice("🔤 vocabulary boosting engaged; terms=\(vocabulary.count, privacy: .public)")
                lastBoosting = .init(outcome: .engaged, termCount: vocabulary.count, terms: vocabulary)
                return TextNormalizer.shared.normalizeSentence(boosted)
            } catch {
                lastBoosting = .init(outcome: Self.boostingFallbackOutcome(for: error),
                                     termCount: vocabulary.count, terms: vocabulary)
                logger.notice("vocabulary boosting unavailable; using plain decode: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            // On a non-unified FluidAudio file decode the gate said no (empty
            // vocabulary or the acoustic-boosting policy is off) — record it so
            // the trace shows the gate evaluated, not that M2 silently no-op'd.
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

        return TextNormalizer.shared.normalizeSentence(result.text)
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

    // MARK: - File-based vocabulary boosting

    /// Transcribe a file through FluidAudio's sliding-window manager with custom
    /// vocabulary rescoring applied per window. Throws (→ caller falls back to
    /// the plain decode) if the CTC model isn't on disk or any step fails.
    ///
    /// LIMITATION (accepted, opt-in path only): SlidingWindowAsrManager exposes no
    /// partial-window-failure signal — `failedWindowCount`/`lastWindowError` are
    /// private, and `finish()` throws ONLY when ALL windows fail (which we catch
    /// → plain-decode fallback). A PARTIAL window failure therefore returns a
    /// silently-truncated boosted transcript that we can't detect from here
    /// (reading the count would need a FluidAudio source change — out of scope and
    /// not durable across SPM re-resolve). Risk is bounded: this path is opt-in
    /// (.fast + acoustic-boosting flag). The truncation case is covered by the
    /// manual long-passage regression test, not by code.
    /// Map a thrown boosting error to the trace outcome (observability only).
    private static func boostingFallbackOutcome(for error: Error) -> TranscriptionTrace.BoostingTrace.Outcome {
        switch error {
        case VocabularyBoostingError.ctcModelMissing: return .ctcModelMissing
        case VocabularyBoostingError.emptyContext: return .fellBackToPlainDecode(reason: "empty context")
        case VocabularyBoostingError.bufferFailed: return .fellBackToPlainDecode(reason: "buffer failed")
        default: return .fellBackToPlainDecode(reason: String(error.localizedDescription.prefix(60)))
        }
    }

    private func transcribeWithVocabularyBoosting(
        samples: [Float], version: AsrModelVersion, vocabulary: [String]
    ) async throws -> String {
        logger.notice("🔤 vocabulary boosting attempted; terms=\(vocabulary.count, privacy: .public)")
        let ctcDir = CtcModels.defaultCacheDirectory(for: .ctc110m)
        guard CtcModels.modelsExist(at: ctcDir) else {
            // Never download on the transcribe hot path — prefetch for next time
            // and fall back to the plain decode now.
            logger.notice("🔤 vocabulary boosting: CTC model missing on disk; prefetching, plain decode this time")
            Task.detached { _ = try? await CtcModels.downloadAndLoad(variant: .ctc110m) }
            throw VocabularyBoostingError.ctcModelMissing
        }

        let ctcModels: CtcModels
        if let cached = ctcModelsCache {
            ctcModels = cached
        } else {
            ctcModels = try await CtcModels.load(from: ctcDir, variant: .ctc110m)
            ctcModelsCache = ctcModels
        }

        let context = try await vocabularyContext(for: vocabulary, ctcDir: ctcDir)
        guard !context.terms.isEmpty else {
            logger.notice("🔤 vocabulary boosting: empty CTC context (no term tokenized); plain decode")
            throw VocabularyBoostingError.emptyContext
        }
        guard let buffer = Self.pcmBuffer(fromFloatSamples: samples) else {
            throw VocabularyBoostingError.bufferFailed
        }

        let models = try await getOrLoadModels(for: version)
        let manager = SlidingWindowAsrManager(config: .default)
        do {
            try await manager.loadModels(models)
            try await manager.configureVocabularyBoosting(vocabulary: context, ctcModels: ctcModels)
            try await manager.startStreaming()
            await manager.streamAudio(buffer)
            let text = try await manager.finish()
            await manager.cleanup()
            return text
        } catch {
            await manager.cleanup()
            throw error
        }
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

    /// Wrap normalized 16 kHz mono `[Float]` samples in an `AVAudioPCMBuffer`
    /// (the format `SlidingWindowAsrManager.streamAudio` expects).
    private static func pcmBuffer(fromFloatSamples samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }
        return buffer
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
