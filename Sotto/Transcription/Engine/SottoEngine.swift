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
    var failurePublishedDuringRun = false

    /// Last model name a `.didChangeModel` notification carried — lets
    /// `handleModelChange` skip a redundant streaming-cache eviction when the
    /// notification fires for the model that's already active.
    var lastNotifiedModelName: String?

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
    var lastStopTimestamp: (date: Date, generation: Int)?

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
    let pipeline: TranscriptionPipeline
    let failureRegistry: FailureRegistry

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

}
