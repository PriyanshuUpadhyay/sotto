import Foundation
import os

/// The enhancement surface collapsed to a single on-device path: Apple
/// Foundation Models (AFM). The former multi-provider selection (MLX / Local
/// CLI / cloud) was removed; this enum is retained as a single case so the
/// rest of the app keeps a stable provider identity.
enum AIProvider: String, CaseIterable, Codable {
    case foundationModels = "Apple Foundation Models"

    init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer().decode(String.self)
        self = .foundationModels
    }
}

class AIService: ObservableObject {
    @Published var isAPIKeyValid: Bool = false

    /// Fixed to AFM. Kept as a published property so existing observers that
    /// react to provider/config changes continue to fire.
    @Published var selectedProvider: AIProvider = .foundationModels

    private static let validityLogger = Logger(subsystem: OSLogSubsystems.app, category: "AIService.validity")

    @available(macOS 26.0, *)
    private static var sharedAFMProvider: AFMProvider = AFMProvider()

    private static func afmAvailable() -> Bool {
        if #available(macOS 26.0, *) { return AFMProvider.isAvailable }
        return false
    }

    /// Injected so tests can drive availability changes without a real
    /// macOS 26 / Apple Intelligence environment.
    private let availabilityProvider: () -> Bool

    init(availabilityProvider: @escaping () -> Bool = { AIService.afmAvailable() }) {
        self.availabilityProvider = availabilityProvider
        self.isAPIKeyValid = availabilityProvider()
    }

    /// Recomputes `isAPIKeyValid` from live AFM availability (Apple Intelligence
    /// can be toggled at runtime).
    func refreshAPIKeyValidity() {
        let newValue = availabilityProvider()
        if newValue != isAPIKeyValid {
            AIService.validityLogger.notice("🦾 afm validity: \(self.isAPIKeyValid, privacy: .public) → \(newValue, privacy: .public)")
            isAPIKeyValid = newValue
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    /// Non-mutating live availability probe — does NOT publish `isAPIKeyValid`.
    /// Safe to call from a SwiftUI body / computed getter (e.g.
    /// `AIEnhancementService.isConfigured`), unlike `refreshAPIKeyValidity()`.
    func checkAvailabilityNow() -> Bool {
        availabilityProvider()
    }

    @available(macOS 26.0, *)
    /// `transcriptChars` is the length of the raw transcript inside `userPrompt`
    /// (which also carries the instruction wrapper + context) — logged as the
    /// timings CSV's `transcriptChars` column so it's comparable to `outputChars`.
    func enhanceWithAFM(
        systemPrompt: String,
        userPrompt: String,
        transcriptChars: Int,
        callKind: EnhancementTimingLogger.CallKind,
        generation: Int
    ) async throws -> String {
        try await AIService.sharedAFMProvider.enhance(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            transcriptChars: transcriptChars,
            callKind: callKind,
            generation: generation
        )
    }

    /// Hidden `EnhancementProviderMLX` experiment path — see `MLXProvider`.
    /// Rebuilt whenever the selected model id changes, since `MLXProvider`
    /// binds its model at init and caches the loaded weights.
    private static var sharedMLXProvider: MLXProvider?

    private static func mlxProvider(for modelId: String) -> MLXProvider {
        if let existing = sharedMLXProvider, existing.modelId == modelId { return existing }
        let provider = MLXProvider(modelId: modelId)
        sharedMLXProvider = provider
        return provider
    }

    /// True when the hidden flag is on AND the selected model's weights are
    /// actually on disk. A flag-on-but-missing-weights state must fall through
    /// to AFM rather than fail the dictation.
    static var isMLXEnhancementReady: Bool {
        UserDefaults.standard.bool(forKey: "EnhancementProviderMLX")
            && MLXModelDownloader.isDownloaded(MLXModelRegistry.selectedModelId)
    }

    func enhanceWithMLX(
        systemPrompt: String,
        userPrompt: String,
        transcriptChars: Int,
        callKind: EnhancementTimingLogger.CallKind
    ) async throws -> (text: String, modelId: String) {
        let modelId = MLXModelRegistry.selectedModelId
        let text = try await AIService.mlxProvider(for: modelId).enhance(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            transcriptChars: transcriptChars,
            callKind: callKind
        )
        return (text, modelId)
    }

    /// Pages AFM base weights without running enhance. Fire-and-forget; swallows
    /// errors. Fired from the prewarm path (wake/launch).
    func warmAFM(source: String) async {
        if #available(macOS 26.0, *) {
            guard AFMProvider.isAvailable else { return }
            await AIService.sharedAFMProvider.warm(source: source)
        }
    }

    /// Warms AFM with the prospective enhance *instructions* so the matching
    /// `enhance(...)` reuses an already-prefilled session (lower ttft).
    /// `generation` is tagged onto the warm so a DIFFERENT dictation's
    /// `enhance(...)` can never consume it — see `AFMProvider.warmedGeneration`.
    func warmAFM(instructions: String, source: String, generation: Int) async {
        if #available(macOS 26.0, *) {
            guard AFMProvider.isAvailable else { return }
            await AIService.sharedAFMProvider.warm(instructions: instructions, source: source, generation: generation)
        }
    }

    /// Unconditional AFM warm-slot reset — call at the start of every new
    /// dictation. Self-gates on availability like the other AFM entry points.
    func resetAFMForNewDictation() async {
        if #available(macOS 26.0, *) {
            await AIService.sharedAFMProvider.reset()
        }
    }
}
