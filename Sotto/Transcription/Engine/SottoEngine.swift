import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import Combine
import os

@MainActor
class SottoEngine: NSObject, ObservableObject {
    /// Engine state. Failures are emitted as one-shot events via
    /// `failurePublisher`; the engine never sustains a failed state — it
    /// returns to `.idle` immediately so the view layer's failure lifetime is
    /// owned by `FailureRegistry`.
    @Published var recordingState: RecordingState = .idle {
        didSet {
            // `isWarmingUp` is only meaningful during `.transcribing`; once the
            // pipeline moves on (enhancing / idle) the transcript has arrived,
            // so the cold-start "warming up" label must clear.
            if recordingState != .transcribing { isWarmingUp = false }
        }
    }
    @Published var shouldCancelRecording = false

    /// True when transcription began before the active model finished loading
    /// (cold start). The recorder HUD reads this to show "warming up" instead
    /// of "transcribing", so a long first-dictation load doesn't read as a
    /// freeze. Cleared automatically when `recordingState` leaves `.transcribing`.
    @Published var isWarmingUp: Bool = false
    /// Live streaming partial from Parakeet/FluidAudio sessions, surfaced in the
    /// recorder capsule's mono tail (`MatteCapsuleView`). `@Published` so the
    /// constellation views (which `@ObservedObject` the engine via
    /// `RecorderStateProvider`) re-render as words arrive. Stays "" for batch-only
    /// Whisper models, so the tail hides gracefully.
    @Published var partialTranscript: String = ""
    var currentSession: TranscriptionSession?

    /// Latest `PasteEvent` republished from `Notification.Name.sottoDidPaste`.
    /// Drives the Constellation orchestrator's `.done` derivation (plan §P1.G).
    /// Mutated on the main actor inside `handleDidPaste`.
    @Published var lastPasteEvent: PasteEvent?

    /// Spec §4.2 first-audio gate. `RecorderUIManager.mapEngineState` reads
    /// `firstAudioObserved` to decide whether to render `.armed` or `.recording`.
    let firstAudioGate = FirstAudioGate()

    var firstAudioObserved: Bool { firstAudioGate.observed }

    /// One-shot failure events. `FailureRegistry` subscribes externally; the
    /// engine has no awareness of the registry. Each `send` carries a fresh
    /// `FailureEvent` (UUID + reason + timestamp).
    let failurePublisher = PassthroughSubject<FailureEvent, Never>()

    /// Tracks whether the in-flight `runPipeline` published a failure. Reset
    /// at the top of each run; flipped true inside the `onFailure` closure.
    /// Guards the tail `failureRegistry.clearAll()` so a run that just
    /// surfaced a failure doesn't immediately wipe its own publish.
    private var failurePublishedDuringRun = false

    /// Last model name a `.didChangeModel` notification carried — lets
    /// `handleModelChange` skip a redundant streaming-cache eviction when the
    /// notification fires for the model that's already active.
    private var lastNotifiedModelName: String?

    /// Set when the user stops recording (`toggleRecord`); read by
    /// `handleDidPaste` to log the X1/F6 acceptance-evidence stop→paste span.
    /// Tagged with the dictation generation active at stop time. Consumed
    /// ONLY when the arriving `PasteEvent` carries a MATCHING
    /// `dictationGeneration` token — that token is set exclusively by
    /// `TranscriptionPipeline.performPaste` (`CursorPaster.pasteAtCursor(...,
    /// dictationGeneration:)`), so "Paste Last Transcription", the command
    /// palette, and review-tray re-paste — which all post the same
    /// `.sottoDidPaste` notification with no token — can never be mistaken
    /// for this dictation's own paste just because no newer recording has
    /// started yet. Also cleared explicitly (belt-and-suspenders, not load-
    /// bearing now that the token exists) on every non-paste terminal path:
    /// cancel / no-recorded-file here, and pipeline cancellation inside
    /// `runPipeline`'s `onCleanup`. NOT cleared on `onFailure` — enhancement
    /// failure falls through to a raw-transcript paste, so that path still
    /// needs the stop timestamp; only transcription failure is a true
    /// terminal there, and the token match alone covers it correctly.
    private var lastStopTimestamp: (date: Date, generation: Int)?

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

    let logger = Logger(subsystem: OSLogSubsystems.app, category: "SottoEngine")

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
            .appendingPathComponent(AppSupport.directoryName)
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

        setupNotifications()
        createRecordingsDirectoryIfNeeded()

        recorder.onRawAudioDb = { [weak self] db in
            Task { @MainActor in self?.firstAudioGate.consume(rawDb: db) }
        }
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
                NotificationManager.shared.showNotification(title: "No AI Model Selected", type: .error)
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
                                    await NotificationManager.shared.showNotification(title: "Recording failed to start", type: .error)
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

    // MARK: - Hands-free commit (W12.D)

    /// W12.D hands-free commit: stop the current recording, run the pipeline
    /// for the captured utterance, then optionally start a new recording so
    /// the next utterance can begin immediately. Each utterance is its own
    /// `Transcription` row (matches existing schema).
    ///
    /// - Parameter restartAfter: `true` (hands-free in progress) → re-arm the
    ///   recorder for the next utterance. `false` (session ending or one-shot
    ///   drain) → leave the recorder stopped.
    ///
    /// This method calls `toggleRecord` directly (rather than tearing the
    /// recorder panel down) so the panel stays visible across utterance commits.
    func commitUtterance(restartAfter: Bool = true) async {
        guard recordingState == .recording else {
            logger.notice("🦾 hands-free: commitUtterance skipped — state=\(String(describing: self.recordingState), privacy: .public)")
            return
        }
        logger.notice("🦾 hands-free: commitUtterance restartAfter=\(restartAfter, privacy: .public)")

        // Stop + run pipeline via the existing toggleRecord flow.
        await toggleRecord()

        guard restartAfter else { return }

        // Wait for recordingState to settle to .idle. The pipeline tail in
        // runPipeline sets recordingState back to .idle at `:292-294`. Use a
        // bounded spin-wait so a slow pipeline doesn't permanently block the
        // hands-free session.
        var spins = 0
        while recordingState != .idle, spins < 100 {
            try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms
            spins += 1
        }
        guard recordingState == .idle else {
            logger.error("🦾 hands-free: commitUtterance abort — recordingState=\(String(describing: self.recordingState), privacy: .public) after pipeline spin-wait")
            return
        }
        // Re-arm.
        await toggleRecord()
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

        // Captured ONCE here — when THIS run begins — not re-read at paste
        // time. A review-before-paste editor can defer this run's own paste
        // by an arbitrary amount; a NEW dictation can start (bumping the
        // shared `dictationGeneration`) in that window. Reading fresh at
        // paste time would then stamp this run's paste with the NEWER
        // dictation's generation instead of its own, letting it wrongly
        // match that newer dictation's (possibly still-uncleared) stop
        // timestamp. Passed straight through to `TranscriptionPipeline.run`,
        // which threads it into every `performPaste` call unchanged.
        let dictationGeneration = enhancementService?.dictationGeneration ?? 0

        await pipeline.run(
            transcription: transcription,
            audioURL: audioURL,
            model: model,
            session: session,
            dictationGeneration: dictationGeneration,
            onStateChange: { [weak self] state in self?.recordingState = state },
            onFailure: { [weak self] reason in
                guard let self else { return }
                // Generation-scoped like the teardown below: a stale run must
                // not publish failure UI — or set the shared
                // `failurePublishedDuringRun` flag — while a newer dictation
                // is active.
                guard (self.enhancementService?.dictationGeneration ?? 0) == dictationGeneration else {
                    self.logger.notice("onFailure skipped – newer dictation active")
                    return
                }
                // NOT a no-paste terminal: transcription-failure IS terminal,
                // but enhancement-failure falls through and still pastes the
                // raw transcript (TranscriptionPipeline.run's catch block
                // continues to its paste tail instead of returning) — clearing
                // `lastStopTimestamp` here would drop stop→paste telemetry on
                // every raw-fallback run. The paste token match in
                // `handleDidPaste` already prevents any false attribution.
                self.failurePublisher.send(FailureEvent(reason: reason))
                self.failurePublishedDuringRun = true
            },
            shouldCancel: { [weak self] in self?.shouldCancelRecording ?? false },
            onCleanup: { [weak self] in
                // Pipeline aborted early via `shouldCancel()` — same reasoning
                // as `onFailure`: this run will never paste.
                self?.lastStopTimestamp = nil
                await self?.releaseResourcesAfterDictation()
            },
            onPreviewShown: { [weak self] in
                // Stop→preview-shown span: stop → review panel on screen. When
                // enhancement runs, the panel presents at enhance-START (raw
                // editable), so the span covers transcribe + UI present only —
                // enhancement lands into the already-visible panel. Same stop +
                // generation match as `handleDidPaste`, but does NOT consume
                // `lastStopTimestamp` — the preview precedes the paste, and the
                // paste span still needs it.
                guard let self, let stopInfo = self.lastStopTimestamp,
                      stopInfo.generation == dictationGeneration else { return }
                let elapsed = Date().timeIntervalSince(stopInfo.date)
                Task { await EnhancementTimingLogger.shared.recordStopToPreview(seconds: elapsed) }
            },
            onDismiss: { [weak self] keepForReview in
                guard let self else { return }
                // Generation-scoped: this pipeline's tail can now run while a
                // NEWER dictation is already recording (the review editor pastes
                // mid-enhance and the user re-records; `beginNewDictation` bumped
                // the shared counter). Tearing down then would stop the new
                // recording's session and hide its UI.
                guard (self.enhancementService?.dictationGeneration ?? 0) == dictationGeneration else {
                    self.logger.notice("onDismiss skipped – newer dictation active")
                    return
                }
                await self.recorderUIManager?.dismissMiniRecorder(deferWindowHideForReview: keepForReview)
            }
        )

        // Same generation scope as `onDismiss`: don't reset a newer dictation's
        // cancel flag or flip its `.recording` state back to `.idle`.
        guard (enhancementService?.dictationGeneration ?? 0) == dictationGeneration else {
            logger.notice("runPipeline tail skipped – newer dictation active")
            return
        }

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
    private func currentModelIsWarm() async -> Bool {
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
