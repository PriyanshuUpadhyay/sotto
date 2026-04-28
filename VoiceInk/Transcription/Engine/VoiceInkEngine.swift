import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import Combine
import os

@MainActor
class VoiceInkEngine: NSObject, ObservableObject {
    /// Engine state. Failures are emitted as one-shot events via
    /// `failurePublisher`; the engine never sustains a failed state — it
    /// returns to `.idle` immediately so the view layer's failure lifetime is
    /// owned by `FailureRegistry`.
    @Published var recordingState: RecordingState = .idle
    @Published var shouldCancelRecording = false
    var partialTranscript: String = ""
    var currentSession: TranscriptionSession?

    /// Latest `PasteEvent` republished from `Notification.Name.voiceInkDidPaste`.
    /// Drives the Constellation orchestrator's `.done` derivation (plan §P1.G).
    /// Mutated on the main actor inside `handleDidPaste`.
    @Published var lastPasteEvent: PasteEvent?

    /// One-shot failure events. `FailureRegistry` subscribes externally; the
    /// engine has no awareness of the registry. Each `send` carries a fresh
    /// `FailureEvent` (UUID + reason + timestamp).
    let failurePublisher = PassthroughSubject<FailureEvent, Never>()

    /// Tracks whether the in-flight `runPipeline` published a failure. Reset
    /// at the top of each run; flipped true inside the `onFailure` closure.
    /// Guards the tail `failureRegistry.clearAll()` so a run that just
    /// surfaced a failure doesn't immediately wipe its own publish.
    private var failurePublishedDuringRun = false

    let recorder = Recorder()
    var recordedFile: URL? = nil
    let recordingsDirectory: URL

    // Injected managers
    let whisperModelManager: WhisperModelManager
    let transcriptionModelManager: TranscriptionModelManager
    weak var recorderUIManager: RecorderUIManager?

    let modelContext: ModelContext
    internal let serviceRegistry: TranscriptionServiceRegistry
    let enhancementService: AIEnhancementService?
    private let pipeline: TranscriptionPipeline
    private let failureRegistry: FailureRegistry

    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VoiceInkEngine")

    init(
        modelContext: ModelContext,
        whisperModelManager: WhisperModelManager,
        transcriptionModelManager: TranscriptionModelManager,
        enhancementService: AIEnhancementService? = nil,
        failureRegistry: FailureRegistry
    ) {
        self.modelContext = modelContext
        self.whisperModelManager = whisperModelManager
        self.transcriptionModelManager = transcriptionModelManager
        self.enhancementService = enhancementService
        self.failureRegistry = failureRegistry

        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")

        self.serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: whisperModelManager,
            modelsDirectory: whisperModelManager.modelsDirectory,
            modelContext: modelContext
        )
        self.pipeline = TranscriptionPipeline(
            modelContext: modelContext,
            serviceRegistry: serviceRegistry,
            enhancementService: enhancementService
        )

        super.init()

        if let enhancementService {
            PowerModeSessionManager.shared.configure(engine: self, enhancementService: enhancementService)
        }

        setupNotifications()
        createRecordingsDirectoryIfNeeded()
    }

    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("❌ Error creating recordings directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    func getEnhancementService() -> AIEnhancementService? {
        return enhancementService
    }

    // MARK: - Toggle Record

    func toggleRecord(powerModeId: UUID? = nil) async {
        logger.notice("toggleRecord called – state=\(String(describing: self.recordingState), privacy: .public)")

        if recordingState == .recording {
            partialTranscript = ""
            recordingState = .transcribing
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
                    currentSession?.cancel()
                    currentSession = nil
                    try? FileManager.default.removeItem(at: recordedFile)
                    recordingState = .idle
                    await cleanupResources()
                }
            } else {
                logger.error("❌ No recorded file found after stopping recording")
                currentSession?.cancel()
                currentSession = nil
                failurePublisher.send(FailureEvent(reason: "No recorded audio file"))
                recordingState = .idle
                await cleanupResources()
            }
        } else {
            logger.notice("toggleRecord: entering start-recording branch")
            guard transcriptionModelManager.currentTranscriptionModel != nil else {
                NotificationManager.shared.showNotification(title: "No AI Model Selected", type: .error)
                return
            }
            shouldCancelRecording = false
            partialTranscript = ""

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

                    self.recorder.startRecording(toOutputFile: permanentURL) { result in
                        Task { @MainActor [self] in
                            do {
                                try result.get()
                                self.logger.notice("toggleRecord: audio hardware started successfully")

                                guard self.recorderUIManager?.isMiniRecorderVisible ?? false, !self.shouldCancelRecording else {
                                    self.recorder.stopRecording()
                                    self.recordedFile = nil
                                    self.recordingState = .idle
                                    return
                                }

                                await ActiveWindowService.shared.applyConfiguration(powerModeId: powerModeId)

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
                                        try? await self.serviceRegistry.fluidAudioTranscriptionService.loadModel(for: fluidAudioModel)
                                    }

                                    if let enhancementService = await self.enhancementService {
                                        await MainActor.run {
                                            enhancementService.captureClipboardContext()
                                        }
                                        await enhancementService.captureScreenContext()
                                    }
                                }

                            } catch {
                                self.logger.error("❌ Failed to start recording: \(error.localizedDescription, privacy: .public)")
                                self.failurePublisher.send(FailureEvent(reason: error.localizedDescription))
                                self.recordingState = .idle
                                self.recordedFile = nil
                                await NotificationManager.shared.showNotification(title: "Recording failed to start", type: .error)
                                self.logger.notice("toggleRecord: calling dismissMiniRecorder from error handler")
                                await self.recorderUIManager?.dismissMiniRecorder()
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

    // MARK: - Pipeline Dispatch

    private func runPipeline(on transcription: Transcription, audioURL: URL) async {
        failurePublishedDuringRun = false

        guard let model = transcriptionModelManager.currentTranscriptionModel else {
            transcription.text = "Transcription Failed: No model selected"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
            try? modelContext.save()
            failurePublisher.send(FailureEvent(reason: "No transcription model selected"))
            failurePublishedDuringRun = true
            recordingState = .idle
            return
        }

        let session = currentSession
        currentSession = nil

        await pipeline.run(
            transcription: transcription,
            audioURL: audioURL,
            model: model,
            session: session,
            onStateChange: { [weak self] state in self?.recordingState = state },
            onFailure: { [weak self] reason in
                guard let self else { return }
                self.failurePublisher.send(FailureEvent(reason: reason))
                self.failurePublishedDuringRun = true
            },
            shouldCancel: { [weak self] in self?.shouldCancelRecording ?? false },
            onCleanup: { [weak self] in await self?.cleanupResources() },
            onDismiss: { [weak self] in await self?.recorderUIManager?.dismissMiniRecorder() }
        )

        shouldCancelRecording = false
        if recordingState != .idle {
            recordingState = .idle
        }
        // Clean-run ack: a pipeline that reached the tail without `onFailure`
        // firing observed a successful end-to-end run, so any unresolved
        // failure from a prior run is now stale. Skip the clear when the
        // current run itself published a failure — otherwise we'd wipe the
        // registry one frame after surfacing the very failure we just
        // published, and the cluster + menubar dot would never see it.
        if !failurePublishedDuringRun {
            failureRegistry.clearAll()
        }
    }

    // MARK: - Resource Cleanup

    func cleanupResources() async {
        logger.notice("cleanupResources: releasing model resources")
        await whisperModelManager.cleanupResources()
        await serviceRegistry.cleanup()
        logger.notice("cleanupResources: completed")
    }

    // MARK: - Notification Handling

    func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLicenseStatusChanged),
            name: .licenseStatusChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePromptChange),
            name: .promptDidChange,
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
            name: .voiceInkDidPaste,
            object: nil
        )
    }

    @objc func handleLicenseStatusChanged() {
        pipeline.licenseViewModel = LicenseViewModel()
    }

    @objc func handleDidPaste(_ note: Notification) {
        guard let event = note.userInfo?[PasteEvent.userInfoKey] as? PasteEvent else { return }
        Task { @MainActor [weak self] in
            self?.lastPasteEvent = event
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
}
