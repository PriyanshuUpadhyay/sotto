import Foundation
import AppKit

struct ApplicationState: Codable {
    /// W12.A canonical state. Replaces stored `isEnhancementEnabled: Bool`.
    var enhanceLevel: EnhanceLevel
    var useScreenCaptureContext: Bool
    var useClipboardContext: Bool
    var selectedPromptId: String?
    var selectedAIProvider: String?
    var selectedAIModel: String?
    var selectedLanguage: String?
    var transcriptionModelName: String?

    enum CodingKeys: String, CodingKey {
        case enhanceLevel
        case isEnhancementEnabled  // legacy fallback
        case useScreenCaptureContext, useClipboardContext, selectedPromptId, selectedAIProvider
        case selectedAIModel, selectedLanguage, transcriptionModelName
    }

    init(enhanceLevel: EnhanceLevel,
         useScreenCaptureContext: Bool,
         useClipboardContext: Bool,
         selectedPromptId: String?,
         selectedAIProvider: String?,
         selectedAIModel: String?,
         selectedLanguage: String?,
         transcriptionModelName: String?) {
        self.enhanceLevel = enhanceLevel
        self.useScreenCaptureContext = useScreenCaptureContext
        self.useClipboardContext = useClipboardContext
        self.selectedPromptId = selectedPromptId
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.selectedLanguage = selectedLanguage
        self.transcriptionModelName = transcriptionModelName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let canonical = try c.decodeIfPresent(EnhanceLevel.self, forKey: .enhanceLevel) {
            enhanceLevel = canonical
        } else if let legacyBool = try c.decodeIfPresent(Bool.self, forKey: .isEnhancementEnabled) {
            enhanceLevel = .from(legacyBool: legacyBool)
        } else {
            enhanceLevel = .default
        }
        useScreenCaptureContext = try c.decode(Bool.self, forKey: .useScreenCaptureContext)
        useClipboardContext = try c.decodeIfPresent(Bool.self, forKey: .useClipboardContext) ?? false
        selectedPromptId = try c.decodeIfPresent(String.self, forKey: .selectedPromptId)
        selectedAIProvider = try c.decodeIfPresent(String.self, forKey: .selectedAIProvider)
        selectedAIModel = try c.decodeIfPresent(String.self, forKey: .selectedAIModel)
        selectedLanguage = try c.decodeIfPresent(String.self, forKey: .selectedLanguage)
        transcriptionModelName = try c.decodeIfPresent(String.self, forKey: .transcriptionModelName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enhanceLevel, forKey: .enhanceLevel)
        try c.encode(enhanceLevel != .none, forKey: .isEnhancementEnabled)  // forward-compat
        try c.encode(useScreenCaptureContext, forKey: .useScreenCaptureContext)
        try c.encode(useClipboardContext, forKey: .useClipboardContext)
        try c.encodeIfPresent(selectedPromptId, forKey: .selectedPromptId)
        try c.encodeIfPresent(selectedAIProvider, forKey: .selectedAIProvider)
        try c.encodeIfPresent(selectedAIModel, forKey: .selectedAIModel)
        try c.encodeIfPresent(selectedLanguage, forKey: .selectedLanguage)
        try c.encodeIfPresent(transcriptionModelName, forKey: .transcriptionModelName)
    }
}

struct PowerModeSession: Codable {
    let id: UUID
    let startTime: Date
    var originalState: ApplicationState
}

@MainActor
class PowerModeSessionManager {
    static let shared = PowerModeSessionManager()
    private let sessionKey = "powerModeActiveSession.v1"
    private var isApplyingPowerModeConfig = false

    private weak var stateProvider: (any PowerModeStateProvider)?
    private var enhancementService: AIEnhancementService?

    private init() {
        recoverSession()
    }

    /// Configure with new VoiceInkEngine-based provider.
    func configure(engine: any PowerModeStateProvider, enhancementService: AIEnhancementService) {
        self.stateProvider = engine
        self.enhancementService = enhancementService
    }

    func beginSession(with config: PowerModeConfig) async {
        guard let stateProvider = stateProvider, let enhancementService = enhancementService else {
            print("SessionManager not configured.")
            return
        }

        // Only capture baseline if NO session exists
        if loadSession() == nil {
            let originalState = ApplicationState(
                enhanceLevel: enhancementService.enhanceLevel,
                useScreenCaptureContext: enhancementService.useScreenCaptureContext,
                useClipboardContext: enhancementService.useClipboardContext,
                selectedPromptId: enhancementService.selectedPromptId?.uuidString,
                selectedAIProvider: enhancementService.getAIService()?.selectedProvider.rawValue,
                selectedAIModel: enhancementService.getAIService()?.currentModel,
                selectedLanguage: UserDefaults.standard.string(forKey: "SelectedLanguage"),
                transcriptionModelName: stateProvider.currentTranscriptionModel?.name
            )

            let newSession = PowerModeSession(
                id: UUID(),
                startTime: Date(),
                originalState: originalState
            )
            saveSession(newSession)

            NotificationCenter.default.addObserver(self, selector: #selector(updateSessionSnapshot), name: .AppSettingsDidChange, object: nil)
        }

        // Always apply the new configuration
        isApplyingPowerModeConfig = true
        await applyConfiguration(config)
        isApplyingPowerModeConfig = false
    }

    var hasActiveSession: Bool {
        return loadSession() != nil
    }

    func endSession() async {
        guard let session = loadSession() else { return }

        isApplyingPowerModeConfig = true
        await restoreState(session.originalState)
        isApplyingPowerModeConfig = false

        NotificationCenter.default.removeObserver(self, name: .AppSettingsDidChange, object: nil)

        clearSession()
    }

    @objc func updateSessionSnapshot() {
        guard !isApplyingPowerModeConfig else { return }

        guard var session = loadSession(),
              let stateProvider = stateProvider,
              let enhancementService = enhancementService else { return }

        let updatedState = ApplicationState(
            enhanceLevel: enhancementService.enhanceLevel,
            useScreenCaptureContext: enhancementService.useScreenCaptureContext,
            useClipboardContext: enhancementService.useClipboardContext,
            selectedPromptId: enhancementService.selectedPromptId?.uuidString,
            selectedAIProvider: enhancementService.getAIService()?.selectedProvider.rawValue,
            selectedAIModel: enhancementService.getAIService()?.currentModel,
            selectedLanguage: UserDefaults.standard.string(forKey: "SelectedLanguage"),
            transcriptionModelName: stateProvider.currentTranscriptionModel?.name
        )

        session.originalState = updatedState
        saveSession(session)
    }

    private func applyConfiguration(_ config: PowerModeConfig) async {
        guard let enhancementService = enhancementService,
              let stateProvider = stateProvider else { return }

        await MainActor.run {
            enhancementService.enhanceLevel = config.enhanceLevel
            enhancementService.useScreenCaptureContext = config.useScreenCapture
            enhancementService.useClipboardContext = config.useClipboardContext

            if config.enhanceLevel != .none {
                if let promptId = config.selectedPrompt, let uuid = UUID(uuidString: promptId) {
                    enhancementService.selectedPromptId = uuid
                }

                if let aiService = enhancementService.getAIService() {
                    if let providerName = config.selectedAIProvider, let provider = AIProvider(rawValue: providerName) {
                        aiService.selectedProvider = provider
                    }
                    if let model = config.selectedAIModel {
                        aiService.selectModel(model)
                    }
                }
            }

            if let language = config.selectedLanguage {
                UserDefaults.standard.set(language, forKey: "SelectedLanguage")
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        }

        if let modelName = config.selectedTranscriptionModelName,
           let selectedModel = await stateProvider.allAvailableModels.first(where: { $0.name == modelName }),
           stateProvider.currentTranscriptionModel?.name != modelName {
            await handleModelChange(to: selectedModel)
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .powerModeConfigurationApplied, object: nil)
        }
    }

    private func restoreState(_ state: ApplicationState) async {
        guard let enhancementService = enhancementService,
              let stateProvider = stateProvider else { return }

        await MainActor.run {
            enhancementService.enhanceLevel = state.enhanceLevel
            enhancementService.useScreenCaptureContext = state.useScreenCaptureContext
            enhancementService.useClipboardContext = state.useClipboardContext
            enhancementService.selectedPromptId = state.selectedPromptId.flatMap(UUID.init)

            if let aiService = enhancementService.getAIService() {
                if let providerName = state.selectedAIProvider, let provider = AIProvider(rawValue: providerName) {
                    aiService.selectedProvider = provider
                }
                if let model = state.selectedAIModel {
                    aiService.selectModel(model)
                }
            }

            if let language = state.selectedLanguage {
                UserDefaults.standard.set(language, forKey: "SelectedLanguage")
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        }

        if let modelName = state.transcriptionModelName,
           let selectedModel = await stateProvider.allAvailableModels.first(where: { $0.name == modelName }),
           stateProvider.currentTranscriptionModel?.name != modelName {
            await handleModelChange(to: selectedModel)
        }
    }

    private func handleModelChange(to newModel: any TranscriptionModel) async {
        guard let stateProvider = stateProvider else { return }

        await stateProvider.setDefaultTranscriptionModel(newModel)

        switch newModel.provider {
        case .whisper:
            await stateProvider.cleanupModelResources()
            if let whisperModel = await stateProvider.availableModels.first(where: { $0.name == newModel.name }) {
                do {
                    try await stateProvider.loadModel(whisperModel)
                } catch {
                    print("Power Mode: Failed to load local model '\(whisperModel.name)': \(error)")
                }
            }
        case .fluidAudio:
            await stateProvider.cleanupModelResources()
        default:
            await stateProvider.cleanupModelResources()
        }
    }

    private func recoverSession() {
        guard let session = loadSession() else { return }
        print("Recovering abandoned Power Mode session.")
        Task {
            await endSession()
        }
    }

    private func saveSession(_ session: PowerModeSession) {
        do {
            let data = try JSONEncoder().encode(session)
            UserDefaults.standard.set(data, forKey: sessionKey)
        } catch {
            print("Error saving Power Mode session: \(error)")
        }
    }

    private func loadSession() -> PowerModeSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        do {
            return try JSONDecoder().decode(PowerModeSession.self, from: data)
        } catch {
            print("Error loading Power Mode session: \(error)")
            return nil
        }
    }

    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }
}
