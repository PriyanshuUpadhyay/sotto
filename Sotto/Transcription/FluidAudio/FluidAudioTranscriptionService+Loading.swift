import Foundation
import CoreML
import AVFoundation
import FluidAudio
import SwiftData
import os.log
import Darwin

extension FluidAudioTranscriptionService {
    func version(for model: any TranscriptionModel) throws -> AsrModelVersion {
        guard let version = FluidAudioModelManager.knownAsrVersion(for: model.name) else {
            logger.error("Unsupported FluidAudio model id: \(model.name, privacy: .public)")
            throw SottoEngineError.unsupportedFluidAudioModel(model.name)
        }
        return version
    }

    func ensureModelsLoaded(for version: AsrModelVersion) async throws {
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

    func ensureUnifiedModelsLoaded() async throws {
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
}
