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
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ModelPrewarm")
    private lazy var serviceRegistry = TranscriptionServiceRegistry(
        modelProvider: whisperModelManager,
        modelsDirectory: whisperModelManager.modelsDirectory,
        modelContext: modelContext
    )
    private let prewarmAudioURL = Bundle.main.url(forResource: "esc", withExtension: "wav")
    private let prewarmEnabledKey = "PrewarmModelOnWake"

    init(
        transcriptionModelManager: TranscriptionModelManager,
        whisperModelManager: WhisperModelManager,
        modelContext: ModelContext,
        enhancementService: AIEnhancementService? = nil
    ) {
        self.transcriptionModelManager = transcriptionModelManager
        self.whisperModelManager = whisperModelManager
        self.modelContext = modelContext
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
            try? await Task.sleep(for: .seconds(3))
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
        // model is currently selected.
        if let currentModel = transcriptionModelManager.currentTranscriptionModel,
           transcriptionPrewarmable(currentModel) {
            if let audioURL = prewarmAudioURL {
                logger.notice("Prewarming \(currentModel.displayName, privacy: .public)")
                let startTime = Date()
                do {
                    let _ = try await serviceRegistry.transcribe(audioURL: audioURL, model: currentModel)
                    let duration = Date().timeIntervalSince(startTime)
                    logger.notice("Prewarm completed in \(String(format: "%.2f", duration), privacy: .public)s")
                } catch {
                    logger.error("❌ Prewarm failed: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                logger.error("❌ Prewarm audio file (esc.wav) not found")
            }
        }

        // W11.A1: MLX enhance prewarm — orthogonal to transcription model. Loads
        // weights into memory so first-enhance-after-wake skips cold-load. No-op
        // when MLX isn't the active enhance provider OR no model is downloaded.
        if isMLXEnhanceProviderReady(), let enhancementService {
            let warmStart = Date()
            await enhancementService.warmMLXIfSelected(source: source)
            let warmDuration = Date().timeIntervalSince(warmStart)
            logger.notice("MLX warm completed in \(String(format: "%.2f", warmDuration), privacy: .public)s")
        }

        // W11.B: AFM prewarm — fired whenever Apple Foundation Models is
        // available, because the AFM-first routing path can flip in mid-
        // session as the user toggles Apple Intelligence in System Settings.
        // The hook itself is cheap (`LanguageModelSession.prewarm()`).
        if #available(macOS 26.0, *), AFMProvider.isAvailable, let enhancementService {
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

        // W11.A1: MLX enhance prewarm path — orthogonal to transcription. Returns
        // true when MLX is the selected enhance provider and the model is
        // downloaded; performPrewarm() dispatches the actual warm.
        if isMLXEnhanceProviderReady() {
            return true
        }

        // W11.B: AFM prewarm fires whenever Apple Foundation Models is
        // available, regardless of provider selection. The AFM-first
        // routing kicks in for `.mlx` users too.
        if #available(macOS 26.0, *), AFMProvider.isAvailable {
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

    /// W11.A1: true when MLX is the active enhance provider and a model is
    /// downloaded. The active-provider check requires an `AIEnhancementService`
    /// reference — without it (e.g. construction order race), we still allow
    /// prewarm based on the downloaded-model state and let `warmMLXIfSelected`
    /// no-op if MLX isn't actually selected.
    private func isMLXEnhanceProviderReady() -> Bool {
        let modelId = UserDefaults.standard.string(forKey: "mlx_selected_model_id") ?? ""
        guard !modelId.isEmpty else { return false }
        guard MLXModelDownloader.status(for: modelId) == .downloaded else { return false }
        if let enhancementService {
            return enhancementService.aiService.selectedProvider == .mlx
        }
        return true
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.notice("ModelPrewarmService deinitialized")
    }
}
