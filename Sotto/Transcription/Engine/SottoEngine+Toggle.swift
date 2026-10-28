import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import Combine
import os

extension SottoEngine {
    // MARK: - Toggle Record

    func toggleRecord() async {
        logger.notice("toggleRecord called – state=\(String(describing: self.recordingState), privacy: .public)")

        if recordingState == .recording {
            partialTranscript = ""
            firstAudioGate.reset()
            recordingState = .transcribing
            lastStopTimestamp = (Date(), enhancementService?.dictationGeneration ?? 0)
            isWarmingUp = await !currentModelIsWarm()
            await recorder.stopRecording()

            if let recordedFile {
                if !shouldCancelRecording {
                    let transcription = Transcription(
                        text: "",
                        duration: 0,
                        audioFileURL: recordedFile.absoluteString,
                        transcriptionStatus: .pending
                    )
                    modelContext.insert(transcription)
                    try? modelContext.save()
                    NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)

                    await runPipeline(on: transcription, audioURL: recordedFile)
                } else {
                    // No pipeline will run for this stop — it can never paste.
                    // Clear now rather than leave it for generation-matching
                    // alone to (imperfectly) guard against: an UNRELATED paste
                    // (e.g. "Paste Last Transcription") firing before the next
                    // recording starts would otherwise still see a matching
                    // generation and wrongly consume this stale stop.
                    lastStopTimestamp = nil
                    currentSession?.cancel()
                    currentSession = nil
                    try? FileManager.default.removeItem(at: recordedFile)
                    recordingState = .idle
                    await releaseResourcesAfterDictation()
                }
            } else {
                logger.error("❌ No recorded file found after stopping recording")
                lastStopTimestamp = nil
                currentSession?.cancel()
                currentSession = nil
                failurePublisher.send(FailureEvent(reason: "No recorded audio file"))
                recordingState = .idle
                await releaseResourcesAfterDictation()
            }
        } else {
            logger.notice("toggleRecord: entering start-recording branch")
            // If a review-before-paste editor is still open (the user dictated,
            // didn't press ⌘↵, and started a new recording), auto-commit it —
            // paste the previous transcript into the focused field — then record
            // the next one. No-op when nothing is pending.
            ComposeReviewWindowManager.shared.commit()
            guard transcriptionModelManager.currentTranscriptionModel != nil else {
                NotificationManager.shared.showNotification(
                    title: "No transcription model selected — pick one to start dictating",
                    type: .error,
                    actionButton: (label: "CHOOSE MODEL",
                                   action: { SottoWindowCoordinator.shared.open(settingsTab: .models) })
                )
                return
            }
            shouldCancelRecording = false
            partialTranscript = ""
            firstAudioGate.start()

            requestRecordPermission { [self] granted in
                if granted {
                    let fileName = "\(UUID().uuidString).wav"
                    let permanentURL = self.recordingsDirectory.appendingPathComponent(fileName)
                    self.recordedFile = permanentURL

                    let pendingChunks = OSAllocatedUnfairLock(initialState: [Data]())
                    self.recorder.onAudioChunk = { data in
                        pendingChunks.withLock { $0.append(data) }
                    }

                    self.recordingState = .recording
                    self.logger.notice("toggleRecord: state=recording, starting audio hardware")
                    // Bumped SYNCHRONOUSLY, before any of the async record-start
                    // work below — scopes every context write (selected text,
                    // clipboard, screen, active-app/vocab snapshot, AFM warm)
                    // to THIS dictation, so a delayed write from an
                    // older/cancelled/superseded one can never land here.
                    let dictationGeneration = self.enhancementService?.beginNewDictation() ?? 0

                    // `startRecording` awaits any in-flight stop internally;
                    // this call site is sync, so the await is wrapped here.
                    Task { @MainActor [self] in
                        await self.recorder.startRecording(toOutputFile: permanentURL) { result in
                            Task { @MainActor [self] in
                                do {
                                    try result.get()
                                    self.logger.notice("toggleRecord: audio hardware started successfully")

                                    guard self.recorderUIManager?.isMiniRecorderVisible ?? false, !self.shouldCancelRecording else {
                                        await self.recorder.stopRecording()
                                        self.recordedFile = nil
                                        self.recordingState = .idle
                                        return
                                    }

                                    if self.recordingState == .recording,
                                       let model = self.transcriptionModelManager.currentTranscriptionModel {
                                        let session = self.serviceRegistry.createSession(
                                            for: model,
                                            onPartialTranscript: { [weak self] partial in
                                                Task { @MainActor in
                                                    self?.partialTranscript = partial
                                                }
                                            }
                                        )
                                        self.currentSession = session
                                        let realCallback = try await session.prepare(model: model)

                                        if let realCallback {
                                            self.recorder.onAudioChunk = realCallback
                                            let buffered = pendingChunks.withLock { chunks -> [Data] in
                                                let result = chunks
                                                chunks.removeAll()
                                                return result
                                            }
                                            for chunk in buffered { realCallback(chunk) }
                                        } else {
                                            self.recorder.onAudioChunk = nil
                                            pendingChunks.withLock { $0.removeAll() }
                                        }
                                    }

                                    Task.detached { [weak self] in
                                        guard let self else { return }

                                        if let model = await self.transcriptionModelManager.currentTranscriptionModel,
                                           model.provider == .whisper {
                                            if let localWhisperModel = await self.whisperModelManager.availableModels.first(where: { $0.name == model.name }),
                                               await self.whisperModelManager.whisperContext == nil {
                                                do {
                                                    try await self.whisperModelManager.loadModel(localWhisperModel)
                                                } catch {
                                                    await self.logger.error("❌ Model loading failed: \(error.localizedDescription, privacy: .public)")
                                                }
                                            }
                                        } else if let fluidAudioModel = await self.transcriptionModelManager.currentTranscriptionModel as? FluidAudioModel {
                                            // A distinct streaming manager (cache-backed or agreement-based)
                                            // already loads its own weights via session.prepare() above —
                                            // the batch manager here would be entirely wasted for it.
                                            let servedByStreaming = await self.serviceRegistry.supportsStreaming(model: fluidAudioModel)
                                            if !servedByStreaming {
                                                try? await self.serviceRegistry.fluidAudioTranscriptionService.loadModel(for: fluidAudioModel)
                                            }
                                        }

                                        if let enhancementService = await self.enhancementService {
                                            await MainActor.run {
                                                enhancementService.captureClipboardContext(generation: dictationGeneration)
                                                // X1/F6: kick off the selected-text fetch here too —
                                                // detached, never gates recording start (already
                                                // started above) — so the post-ASR path awaits a
                                                // cached value instead of paying the AX/menu-Copy
                                                // cost (100s of ms) live.
                                                enhancementService.captureSelectedTextContext(generation: dictationGeneration)
                                                // X1/F7: snapshot the app category + vocabulary ONCE
                                                // here so the warm below and the real post-ASR
                                                // enhance both build byte-identical system
                                                // instructions, even if the user switches apps mid-
                                                // recording.
                                                enhancementService.captureDictationSnapshot(generation: dictationGeneration)
                                            }
                                            await enhancementService.captureScreenContext(generation: dictationGeneration)
                                            // Warm AFM: its time-to-first-token dominates per-enhance
                                            // latency. Recording-start is the ideal warm point — by the
                                            // time ASR finishes and enhance(...) runs, the session is
                                            // hot. Gated by the PrewarmAFMEnhancement A/B kill-switch;
                                            // warmAFMForNextEnhance self-gates on AFM availability.
                                            if UserDefaults.standard.bool(forKey: "PrewarmAFMEnhancement") {
                                                // Warm the actual NEXT-enhance instructions (not just base
                                                // weights) so the matching enhance reuses a prefilled session
                                                // and skips the ttft-dominating instruction prefill.
                                                await enhancementService.warmAFMForNextEnhance(source: "recordingStart", generation: dictationGeneration)
                                            }
                                        }
                                    }

                                } catch {
                                    self.logger.error("❌ Failed to start recording: \(error.localizedDescription, privacy: .public)")
                                    self.failurePublisher.send(FailureEvent(reason: error.localizedDescription))
                                    self.recordingState = .idle
                                    self.recordedFile = nil
                                    await NotificationManager.shared.showNotification(
                                        title: "Recording failed to start",
                                        type: .error,
                                        actionButton: (label: "RETRY",
                                                       action: { NotificationCenter.default.post(name: .retryRecording, object: nil) })
                                    )
                                    self.logger.notice("toggleRecord: calling dismissMiniRecorder from error handler")
                                    await self.recorderUIManager?.dismissMiniRecorder()
                                }
                            }
                        }
                    }
                } else {
                    logger.error("❌ Recording permission denied.")
                }
            }
        }
    }

    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
        response(true)
    }
}
