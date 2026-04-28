import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import os

@MainActor
class VoiceInkEngine: NSObject, ObservableObject {
    /// Engine state. Transitioning to `.failed(reason:)` schedules an automatic
    /// collapse back to `.idle` after `failedDwellSeconds` so the view layer can
    /// render the failure visual (red shake → amber dwell → fade) without the
    /// call site having to manage timers. Starting a new recording cancels any
    /// pending dwell so a fresh `.recording` is never stomped by a stale `.idle`.
    @Published var recordingState: RecordingState = .idle {
        didSet {
            switch recordingState {
            case .failed:
                scheduleFailedDwell()
            case .recording, .starting:
                cancelFailedDwell()
            default:
                break
            }
        }
    }
    @Published var shouldCancelRecording = false
    var partialTranscript: String = ""
    var currentSession: TranscriptionSession?

    /// Latest `PasteEvent` republished from `Notification.Name.voiceInkDidPaste`.
    /// Drives the Constellation orchestrator's `.done` derivation (plan §P1.G).
    /// Mutated on the main actor inside `handleDidPaste`.
    @Published var lastPasteEvent: PasteEvent?

    /// Dwell window for `.failed(reason:)` before collapsing to `.idle`.
    /// Matches spec §3.1: red shake (~0.32s) + amber dwell (~1.2s) ≈ 1.4s.
    static let failedDwellSeconds: Double = 1.4
    private var failedDwellTask: Task<Void, Never>?

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

    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VoiceInkEngine")

    init(
        modelContext: ModelContext,
        whisperModelManager: WhisperModelManager,
        transcriptionModelManager: TranscriptionModelManager,
        enhancementService: AIEnhancementService? = nil
    ) {
        self.modelContext = modelContext
        self.whisperModelManager = whisperModelManager
        self.transcriptionModelManager = transcriptionModelManager
        self.enhancementService = enhancementService

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
                recordingState = .failed(reason: "No recorded audio file")
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
                                self.recordingState = .failed(reason: error.localizedDescription)
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
        guard let model = transcriptionModelManager.currentTranscriptionModel else {
            transcription.text = "Transcription Failed: No model selected"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
            try? modelContext.save()
            recordingState = .failed(reason: "No transcription model selected")
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
            shouldCancel: { [weak self] in self?.shouldCancelRecording ?? false },
            onCleanup: { [weak self] in await self?.cleanupResources() },
            onDismiss: { [weak self] in await self?.recorderUIManager?.dismissMiniRecorder() }
        )

        shouldCancelRecording = false
        // Preserve `.failed` so its dwell can complete; it self-collapses to `.idle`.
        if case .failed = recordingState {
            // dwell timer owns the transition
        } else if recordingState != .idle {
            recordingState = .idle
        }
    }

    // MARK: - Failed dwell

    /// Schedules the `.failed` → `.idle` collapse. Idempotent: replaces any
    /// in-flight dwell so a fresh failure resets the timer.
    private func scheduleFailedDwell() {
        failedDwellTask?.cancel()
        failedDwellTask = Task { @MainActor [weak self] in
            let nanos = UInt64(VoiceInkEngine.failedDwellSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, !Task.isCancelled else { return }
            // Only collapse if we're still dwelling — a new recording or
            // explicit reset may have already moved us elsewhere.
            if case .failed = self.recordingState {
                self.recordingState = .idle
            }
        }
    }

    /// Cancels any pending failure dwell. Called on transitions out of `.failed`
    /// (e.g. user starts a new recording mid-dwell).
    private func cancelFailedDwell() {
        failedDwellTask?.cancel()
        failedDwellTask = nil
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
