import Foundation
import os

/// The enhancement surface supports Apple Foundation Models and local GGUF models.
enum AIProvider: String, CaseIterable, Codable {
    case foundationModels = "Apple Foundation Models"
    case localGGUF = "Local model (GGUF)"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(String.self)
        self = AIProvider(rawValue: raw ?? "") ?? .foundationModels
    }

    /// Recorded against a finished enhancement so history rows name the real
    /// provider.
    var modelIdentifier: String {
        switch self {
        case .foundationModels: return "apple-on-device"
        case .localGGUF: return "gguf-" + GGUFModelRegistry.selectedSlug
        }
    }

    static var defaultsOverride: UserDefaults?
    static var isDownloadedOverride: ((String) -> Bool)?

    /// Resolves the effective provider: returns .localGGUF only when selected
    /// in defaults AND model weights are downloaded; otherwise .foundationModels.
    static func resolved(
        defaults: UserDefaults = defaultsOverride ?? .standard,
        isDownloaded: (String) -> Bool = isDownloadedOverride ?? { GGUFModelRegistry.isDownloaded($0) }
    ) -> AIProvider {
        if defaults.string(forKey: "EnhancementProvider") == AIProvider.localGGUF.rawValue,
           isDownloaded(GGUFModelRegistry.selectedSlug) {
            return .localGGUF
        }
        return .foundationModels
    }
}

class AIService: ObservableObject {
    @Published var isAPIKeyValid: Bool = false

    /// Reflects the resolved provider and updates on .AppSettingsDidChange.
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
    private let ggufAvailabilityProvider: () -> Bool

    var afmEnhanceHandler: ((_ systemPrompt: String, _ userPrompt: String, _ transcriptChars: Int, _ callKind: EnhancementTimingLogger.CallKind, _ generation: Int) async throws -> String)?
    var ggufEnhanceHandler: ((_ systemPrompt: String, _ userPrompt: String, _ transcriptChars: Int, _ callKind: EnhancementTimingLogger.CallKind, _ generation: Int) async throws -> String)?

    init(
        availabilityProvider: @escaping () -> Bool = { AIService.afmAvailable() },
        ggufAvailabilityProvider: @escaping () -> Bool = { GGUFModelRegistry.isDownloaded(GGUFModelRegistry.selectedSlug) }
    ) {
        self.availabilityProvider = availabilityProvider
        self.ggufAvailabilityProvider = ggufAvailabilityProvider
        self.selectedProvider = AIProvider.resolved()
        self.isAPIKeyValid = checkAvailabilityNow()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsDidChange),
            name: .AppSettingsDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleSettingsDidChange() {
        let newProvider = AIProvider.resolved()
        if newProvider != selectedProvider {
            selectedProvider = newProvider
        }
        let newValue = checkAvailabilityNow()
        if newValue != isAPIKeyValid {
            isAPIKeyValid = newValue
        }
    }

    /// Recomputes `isAPIKeyValid` from live availability.
    func refreshAPIKeyValidity() {
        let newProvider = AIProvider.resolved()
        let providerChanged = (newProvider != selectedProvider)
        if providerChanged {
            selectedProvider = newProvider
        }
        let newValue = checkAvailabilityNow()
        if newValue != isAPIKeyValid || providerChanged {
            AIService.validityLogger.notice("🦾 availability validity: \(self.isAPIKeyValid, privacy: .public) → \(newValue, privacy: .public)")
            isAPIKeyValid = newValue
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    /// Non-mutating live availability probe — does NOT publish `isAPIKeyValid`.
    /// Safe to call from a SwiftUI body / computed getter (e.g.
    /// `AIEnhancementService.isConfigured`), unlike `refreshAPIKeyValidity()`.
    func checkAvailabilityNow() -> Bool {
        switch selectedProvider {
        case .foundationModels:
            return availabilityProvider()
        case .localGGUF:
            return ggufAvailabilityProvider()
        }
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
        if let handler = afmEnhanceHandler {
            return try await handler(systemPrompt, userPrompt, transcriptChars, callKind, generation)
        }
        return try await AIService.sharedAFMProvider.enhance(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            transcriptChars: transcriptChars,
            callKind: callKind,
            generation: generation
        )
    }

    private static let sharedGGUFProvider = GGUFProvider()

    static func resetGGUF() {
        Task {
            await sharedGGUFProvider.reset()
        }
    }

    func enhanceWithGGUF(
        systemPrompt: String,
        userPrompt: String,
        transcriptChars: Int,
        callKind: EnhancementTimingLogger.CallKind,
        generation: Int
    ) async throws -> String {
        if let handler = ggufEnhanceHandler {
            return try await handler(systemPrompt, userPrompt, transcriptChars, callKind, generation)
        }
        return try await AIService.sharedGGUFProvider.enhance(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            transcriptChars: transcriptChars,
            callKind: callKind,
            generation: generation
        )
    }

    func warmGGUF(prompt: String? = nil, source: String) async {
        try? await AIService.sharedGGUFProvider.warm(prompt: prompt, source: source)
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
