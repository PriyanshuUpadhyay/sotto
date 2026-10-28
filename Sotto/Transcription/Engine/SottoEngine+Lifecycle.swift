import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import Combine
import os

extension SottoEngine {
    // MARK: - Prewarm

    /// Idempotent transcription-model warm-up, driven by `ModelPrewarmService`
    /// at launch/wake. Loads (and runs one warm inference on the bundled
    /// `esc.wav` clip) through the engine's OWN `serviceRegistry`, so the warmed
    /// FluidAudio/whisper instance is the SAME one real dictation uses — the
    /// single-owner invariant the prewarm previously violated by building its
    /// own registry. The Unified path dedups concurrent loads, so a dictation
    /// arriving mid-warm attaches to this load instead of cold-loading a second
    /// copy and serializing on the ANE.
    ///
    /// Streaming-cache-backed families (Unified/EOU/Nemotron, when actually
    /// served by streaming) warm through `FluidAudioStreamingManagerCache`
    /// instead — its encoder is distinct from the batch one `transcribe(...)`
    /// below would warm, and EOU/Nemotron are streaming-only (batch `transcribe`
    /// throws for them), so they were never warmed at all before this.
    func warmUpTranscriptionModel() async {
        guard let model = transcriptionModelManager.currentTranscriptionModel,
              model.provider == .whisper || model.provider == .fluidAudio else { return }

        if model.provider == .fluidAudio,
           FluidAudioModelManager.isStreamingManagerCacheFamily(named: model.name),
           serviceRegistry.supportsStreaming(model: model) {
            do {
                try await serviceRegistry.fluidAudioStreamingManagerCache.prewarm(for: model)
            } catch {
                logger.error("❌ Streaming model prewarm failed: \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        guard let audioURL = Bundle.main.url(forResource: "esc", withExtension: "wav") else {
            logger.error("❌ Prewarm audio file (esc.wav) not found")
            return
        }
        do {
            _ = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
        } catch {
            logger.error("❌ Transcription prewarm failed: \(error.localizedDescription, privacy: .public)")
        }

        // Acoustic vocabulary boosting is explicit opt-in: the CTC model is a
        // 110 MB download and realtime trace evidence showed the spotter
        // over-confirming the whole vocabulary. Prepare it off the hot path only
        // after the user enables the setting. prepareModel() is idempotent.
        if AcousticBoostingPolicy.isEnabled(forModelNamed: model.name) {
            Task.detached { try? await AcousticVocabularyService.shared.prepareModel() }
        }
    }

    /// Whether the active model's heavy resources are already resident, so the
    /// transcribing phase will be near-instant. Drives the recorder's
    /// "warming up" vs "transcribing" label. Best-effort: providers without a
    /// local warm concept report warm.
    func currentModelIsWarm() async -> Bool {
        guard let model = transcriptionModelManager.currentTranscriptionModel else { return true }
        switch model.provider {
        case .fluidAudio:
            // The actual session provider for the 3 streaming-cache-backed
            // families is FluidAudioStreamingManagerCache, not the batch
            // service — ask it directly instead of reading batch residency.
            if FluidAudioModelManager.isStreamingManagerCacheFamily(named: model.name),
               serviceRegistry.supportsStreaming(model: model) {
                return await serviceRegistry.fluidAudioStreamingManagerCache.isReady(for: model)
            }
            // Agreement-based TDT streaming (FluidAudioStreamingProvider)
            // builds a fresh per-session AsrManager every time, but reuses the
            // batch service's cached AsrModels FILES — that's its real warm
            // signal, not batch AsrManager/isModelLoaded residency (which C2
            // no longer even loads eagerly for this path).
            if serviceRegistry.supportsStreaming(model: model),
               let version = FluidAudioModelManager.knownAsrVersion(for: model.name) {
                return await serviceRegistry.fluidAudioTranscriptionService.isModelFilesCached(for: version)
            }
            return await serviceRegistry.fluidAudioTranscriptionService.isModelLoaded
        case .whisper:
            return whisperModelManager.whisperContext != nil
        default:
            return true
        }
    }

    // MARK: - Resource Cleanup

    func cleanupResources() async {
        logger.notice("cleanupResources: releasing model resources")
        await whisperModelManager.cleanupResources()
        await serviceRegistry.cleanup()
        logger.notice("cleanupResources: completed")
    }

    /// Per-dictation resource teardown. The heavy ASR/whisper model is always
    /// kept resident between dictations, so the next one skips the ~11-21s ANE
    /// cold-load (dropping it per-dictation relied on the OS CoreML/ANE cache,
    /// which evicts after a few idle minutes, surfacing the "warming up" hang).
    /// A deliberate model switch still releases via `cleanupResources()`.
    func releaseResourcesAfterDictation() async {
        logger.notice("releaseResourcesAfterDictation: keeping transcription model warm")
    }

    // MARK: - Notification Handling

    func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePromptChange),
            name: .promptDidChange,
            object: nil
        )
        // Evict the streaming-cache-backed manager on a deliberate model
        // switch — otherwise switching away to Whisper/native/batch FluidAudio
        // leaves the old streaming manager resident indefinitely (nothing else
        // ever calls acquireX() again to naturally evict it).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModelChange(_:)),
            name: .didChangeModel,
            object: nil
        )
        // P1.G — republish CursorPaster's paste event so the Constellation
        // orchestrator can derive `.done` without coupling to NotificationCenter
        // directly. Notifications can arrive on any thread (CursorPaster posts
        // synchronously from `pasteFromClipboard()` running on the main queue
        // today, but the contract leaves room for off-main posts), so the
        // selector hops to the main actor before mutating `lastPasteEvent`.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidPaste(_:)),
            name: .sottoDidPaste,
            object: nil
        )
    }

    @objc func handleDidPaste(_ note: Notification) {
        guard let event = note.userInfo?[PasteEvent.userInfoKey] as? PasteEvent else { return }
        Task { @MainActor [weak self] in
            self?.lastPasteEvent = event
            // X1/F6 acceptance evidence: stop→paste wall-clock. Fire-and-forget,
            // off whatever path led here. Requires the EVENT's own dictation-
            // generation token (set only by the transcription pipeline's own
            // paste, `TranscriptionPipeline.performPaste`) to match the stored
            // stop's generation — generation-matching alone isn't enough,
            // since "Paste Last Transcription" / the command palette / a
            // review-tray re-paste all post the SAME notification with no
            // token, and would otherwise be mistaken for this dictation's own
            // paste merely because no newer recording had started yet.
            if let stopInfo = self?.lastStopTimestamp,
               let pasteGeneration = event.dictationGeneration,
               stopInfo.generation == pasteGeneration {
                self?.lastStopTimestamp = nil
                let elapsed = Date().timeIntervalSince(stopInfo.date)
                Task { await EnhancementTimingLogger.shared.recordStopToPaste(seconds: elapsed) }
            }
        }
    }

    @objc func handlePromptChange() {
        Task {
            let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt")
                ?? whisperModelManager.whisperPrompt.transcriptionPrompt
            if let context = whisperModelManager.whisperContext {
                await context.setPrompt(currentPrompt)
            }
        }
    }

    @objc func handleModelChange(_ note: Notification) {
        let modelName = note.userInfo?["modelName"] as? String
        guard modelName != lastNotifiedModelName else { return }
        lastNotifiedModelName = modelName
        Task { [weak self] in
            await self?.serviceRegistry.fluidAudioStreamingManagerCache.cleanup()
        }
    }
}
