import Foundation
import SwiftData
import os
import AppKit

@MainActor
final class ModelPrewarmService: ObservableObject {
    private let transcriptionModelManager: TranscriptionModelManager
    private let whisperModelManager: WhisperModelManager
    private let modelContext: ModelContext
    /// W11.A1: optional dependency. Injected post-init via the app-level service
    /// container so MLX prewarm can fire alongside transcription model prewarm.
    /// nil-safe: if not wired, MLX prewarm degrades to no-op (recording-start
    /// hook still fires).
    private weak var enhancementService: AIEnhancementService?
    /// The app's single engine. Transcription prewarm routes through
    /// `engine.warmUpTranscriptionModel()` so it warms the SAME
    /// `FluidAudioTranscriptionService`/whisper instance real dictation uses —
    /// previously this service built its own `TranscriptionServiceRegistry`, so
    /// its warm model was invisible to the engine and a mid-warm dictation
    /// cold-loaded a second copy.
    private weak var engine: SottoEngine?
    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "ModelPrewarm")
    private let prewarmEnabledKey = "PrewarmModelOnWake"

    init(
        transcriptionModelManager: TranscriptionModelManager,
        whisperModelManager: WhisperModelManager,
        modelContext: ModelContext,
        engine: SottoEngine? = nil,
        enhancementService: AIEnhancementService? = nil
    ) {
        self.transcriptionModelManager = transcriptionModelManager
        self.whisperModelManager = whisperModelManager
        self.modelContext = modelContext
        self.engine = engine
        self.enhancementService = enhancementService
        setupNotifications()
        schedulePrewarmOnAppLaunch()
    }

    /// W11.A1: injected post-init when the app-level service container is fully
    /// wired and `AIEnhancementService` is available. Safe to call multiple
    /// times.
    func attachEnhancementService(_ service: AIEnhancementService) {
        self.enhancementService = service
    }

    // MARK: - Notification Setup

    private func setupNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        // Trigger on wake from sleep
        center.addObserver(
            self,
            selector: #selector(schedulePrewarm),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        logger.notice("ModelPrewarmService initialized - listening for wake and app launch")
    }

    // MARK: - Trigger Handlers

    /// Trigger on app launch (cold start)
    private func schedulePrewarmOnAppLaunch() {
        logger.notice("App launched, scheduling prewarm")
        Task {
            // The ANE compile of the ASR model is the dominant first-dictation
            // latency (~11-21s cold), so start it ASAP. A short 0.5s yield keeps
            // it off the launch-critical path (window/menu-bar setup) without
            // meaningfully delaying compile start — the old 3s wait just pushed
            // the cold load later, widening the window where an early dictation
            // races the warm.
            try? await Task.sleep(for: .milliseconds(500))
            await performPrewarm(source: "appLaunch")
        }
    }

    /// Trigger on wake from sleep or screen unlock
    @objc private func schedulePrewarm() {
        logger.notice("Mac activity detected (wake/unlock), scheduling prewarm")
        Task {
            try? await Task.sleep(for: .seconds(3))
            await performPrewarm(source: "wake")
        }
    }

    // MARK: - Core Prewarming Logic

    private func performPrewarm(source: String) async {
        guard shouldPrewarm() else { return }

        // Transcription model prewarm — runs only when a local whisper/fluidAudio
        // model is currently selected. Routed through the engine so it warms the
        // SAME transcription-service instance real dictation uses (single-owner
        // invariant); the engine's Unified path dedups a mid-warm dictation onto
        // this load instead of cold-loading a second copy.
        if let currentModel = transcriptionModelManager.currentTranscriptionModel,
           transcriptionPrewarmable(currentModel) {
            logger.notice("Prewarming \(currentModel.displayName, privacy: .public)")
            let startTime = Date()
            await engine?.warmUpTranscriptionModel()
            let duration = Date().timeIntervalSince(startTime)
            logger.notice("Prewarm completed in \(String(format: "%.2f", duration), privacy: .public)s")
        }

        // W11.B: AFM prewarm — fired whenever Apple Foundation Models is
        // available, because the AFM-first routing path can flip in mid-
        // session as the user toggles Apple Intelligence in System Settings.
        // The hook itself is cheap (`LanguageModelSession.prewarm()`).
        //
        // W14.B — granular gate: `PrewarmAFMEnhancement` (default true) lets
        // users disable AFM warm specifically without affecting transcription
        // model prewarm. Useful for empirical A/B of cold-vs-warm AFM ttft.
        if #available(macOS 26.0, *),
           AFMProvider.isAvailable,
           UserDefaults.standard.bool(forKey: "PrewarmAFMEnhancement"),
           let enhancementService {
            let warmStart = Date()
            await enhancementService.warmAFMIfAvailable(source: source)
            let warmDuration = Date().timeIntervalSince(warmStart)
            logger.notice("AFM warm completed in \(String(format: "%.2f", warmDuration), privacy: .public)s")
        }
    }

    // MARK: - Validation

    private func shouldPrewarm() -> Bool {
        // Check if user has enabled prewarming.
        let isEnabled = UserDefaults.standard.bool(forKey: prewarmEnabledKey)
        guard isEnabled else {
            logger.notice("Prewarm disabled by user")
            return false
        }

        // Transcription path: prewarm if active model is a local whisper/fluidAudio.
        if let model = transcriptionModelManager.currentTranscriptionModel,
           transcriptionPrewarmable(model) {
            return true
        }

        // W11.B: AFM prewarm fires whenever Apple Foundation Models is
        // available. W14.B — gated by `PrewarmAFMEnhancement`.
        if #available(macOS 26.0, *),
           AFMProvider.isAvailable,
           UserDefaults.standard.bool(forKey: "PrewarmAFMEnhancement") {
            return true
        }

        logger.notice("Skipping prewarm — no warmable provider")
        return false
    }

    private func transcriptionPrewarmable(_ model: any TranscriptionModel) -> Bool {
        switch model.provider {
        case .whisper, .fluidAudio:
            return true
        default:
            return false
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.notice("ModelPrewarmService deinitialized")
    }
}
