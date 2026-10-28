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
    var asrManager: AsrManager?
    var unifiedAsrManager: UnifiedAsrManager?
    var vadManager: VadManager?
    var activeVersion: AsrModelVersion?
    var cachedModels: AsrModels?
    var loadingTask: (version: AsrModelVersion, task: Task<AsrModels, Error>)?
    // In-flight manager load (model file load + AsrManager.loadModels ANE
    // compile), keyed by version. Same dedup shape as `unifiedLoadingTask`:
    // only the initiator assigns `asrManager`; a same-version joiner awaits
    // this task then re-evaluates. A caller wanting a DIFFERENT version is a
    // version switch, not a join — it waits for this to settle (so it
    // doesn't race the initiator's cleanup) then proceeds as initiator.
    var tdtLoadingTask: (version: AsrModelVersion, task: Task<AsrManager, Error>)?
    var unifiedLoadingTask: Task<UnifiedAsrManager, Error>?
    // In-flight Cohere load, same dedup shape as `unifiedLoadingTask`.
    var cohereLoadingTask: Task<CoherePipeline.LoadedModels, Error>?
    // Bumped at the start of every real (non-cached) family switch in
    // `ensureModelsLoaded`/`ensureUnifiedModelsLoaded`/`ensureCohereModels`.
    // Actor reentrancy at their `await`s lets a second family switch start
    // before the first finishes; whichever switch is about to assign its
    // freshly-loaded manager checks this counter first, and if a newer
    // switch has bumped it since, discards its own load and retries instead
    // of resurrecting a family a newer request already moved past. Cleanup
    // of other families stays unconditional (always correct/idempotent) —
    // only the final assignment is gated.
    var familySwitchGeneration = 0
    // Cohere Transcribe (experimental, batch-only): loaded via CoherePipeline,
    // which has no manager type. Models + pipeline are cached across dictations.
    var cohereModels: CoherePipeline.LoadedModels?
    var coherePipeline: CoherePipeline?
    let logger = Logger(subsystem: OSLogSubsystems.fluidAudio, category: "FluidAudioTranscriptionService")

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
    var ctcModelsCache: CtcModels?
    var ctcTokenizerCache: CtcTokenizer?

    enum VocabularyBoostingError: Error { case ctcModelMissing, emptyContext }
    var boostableCache: (vocabulary: [String], terms: [String])?

    /// Observability ONLY (no behavior): the M2 in-decoder rescore outcome for the
    /// most recent `transcribe(audioURL:model:)` call. Reset to nil at the top of
    /// every transcribe AND at streaming start (via `resetBoostingTrace`), so the
    /// pipeline's post-transcription read reflects this utterance only — a prior
    /// file decode's outcome can't bleed onto a realtime/streaming entry.
    var lastBoosting: TranscriptionTrace.BoostingTrace?

    /// Clear the boosting trace before a streaming (realtime/M1) run, which never
    /// calls `transcribe(audioURL:model:)` and so would otherwise leave a stale
    /// file-decode outcome for the pipeline to misattribute.
    func resetBoostingTrace() { lastBoosting = nil }

    /// Inject the SwiftData container that owns `VocabularyWord`. Called by the
    /// registry at construction; the same actor instance serves every file path.
    func setVocabularyContainer(_ container: ModelContainer) {
        self.vocabularyContainer = container
    }

    func currentVocabulary() -> [String] {
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
