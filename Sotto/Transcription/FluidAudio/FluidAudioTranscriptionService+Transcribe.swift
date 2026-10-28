import Foundation
import CoreML
import AVFoundation
import FluidAudio
import SwiftData
import os.log
import Darwin

extension FluidAudioTranscriptionService {
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
    func ensureCohereModels() async throws -> CoherePipeline.LoadedModels {
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
}
