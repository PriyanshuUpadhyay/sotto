import Foundation
import SwiftUI
import os

/// As of F07, non-imported entries in `allAvailableModels` are sourced from
/// `TranscriptionRegistryLoader.entries()` via `TranscriptionModelMapper`,
/// replacing the deleted static `TranscriptionModelRegistry.curated` array.
/// Cloud and custom-cloud models are appended by the mapper; imported whisper
/// models are appended by `refreshAllAvailableModels()`.
@MainActor
class TranscriptionModelManager: ObservableObject {
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var allAvailableModels: [any TranscriptionModel]

    private weak var whisperModelManager: WhisperModelManager?
    private weak var fluidAudioModelManager: FluidAudioModelManager?

    private let registryLoader = TranscriptionRegistryLoader()

    /// Token for the `.requestModelDownload` observer (onboarding → download).
    private var requestDownloadObserver: NSObjectProtocol?

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "TranscriptionModelManager")

    init(whisperModelManager: WhisperModelManager, fluidAudioModelManager: FluidAudioModelManager) {
        self.whisperModelManager = whisperModelManager
        self.fluidAudioModelManager = fluidAudioModelManager
        self.allAvailableModels = TranscriptionModelMapper.availableModels(using: TranscriptionRegistryLoader())

        // Wire up deletion callbacks so each manager notifies this manager.
        whisperModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }
        fluidAudioModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }

        // Wire up "models changed" callbacks so this manager rebuilds allAvailableModels.
        whisperModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
        fluidAudioModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }

        // Wire up "model downloaded" callbacks so a freshly downloaded model
        // auto-activates into an empty/broken selection (guided setup).
        whisperModelManager.onModelDownloaded = { [weak self] name in
            self?.autoSelectAfterDownload(name)
        }
        fluidAudioModelManager.onModelDownloaded = { [weak self] name in
            self?.autoSelectAfterDownload(name)
        }

        // Observe onboarding's download request (onboarding can't see the managers).
        requestDownloadObserver = NotificationCenter.default.addObserver(
            forName: .requestModelDownload,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let modelId = note.userInfo?["modelId"] as? String else { return }
            Task { @MainActor in
                self?.handleRequestModelDownload(modelId)
            }
        }
    }

    deinit {
        if let requestDownloadObserver {
            NotificationCenter.default.removeObserver(requestDownloadObserver)
        }
    }

    // MARK: - Computed: usable models

    var usableModels: [any TranscriptionModel] {
        allAvailableModels.filter { model in
            switch model.provider {
            case .whisper:
                return whisperModelManager?.availableModels.contains { $0.name == model.name } ?? false
            case .fluidAudio:
                return fluidAudioModelManager?.isFluidAudioModelDownloaded(named: model.name) ?? false
            case .nativeApple:
                if #available(macOS 26, *) { return true } else { return false }
            default:
                return false
            }
        }
    }

    // MARK: - Model loading from UserDefaults

    func loadCurrentTranscriptionModel() {
        if let savedModelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel"),
           let savedModel = allAvailableModels.first(where: { $0.name == savedModelName }) {
            currentTranscriptionModel = savedModel
        }
    }

    // MARK: - Set default model

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        self.currentTranscriptionModel = model
        UserDefaults.standard.set(model.name, forKey: "CurrentTranscriptionModel")

        if model.provider != .whisper {
            whisperModelManager?.loadedWhisperModel = nil
            whisperModelManager?.isModelLoaded = true
        }

        NotificationCenter.default.post(name: .didChangeModel, object: nil, userInfo: ["modelName": model.name])
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    // MARK: - Refresh all available models

    func refreshAllAvailableModels() {
        let currentModelName = currentTranscriptionModel?.name
        var models = TranscriptionModelMapper.availableModels(using: registryLoader)

        for whisperModel in whisperModelManager?.availableModels ?? [] {
            if !models.contains(where: { $0.name == whisperModel.name }) {
                let importedModel = ImportedWhisperModel(fileBaseName: whisperModel.name)
                models.append(importedModel)
            }
        }

        allAvailableModels = models

        if let currentName = currentModelName,
           let updatedModel = allAvailableModels.first(where: { $0.name == currentName }) {
            // Rebind only — persisting here would leak a session-scoped Power
            // Mode override into the saved default if a refresh lands mid-session.
            currentTranscriptionModel = updatedModel
        }
    }

    // MARK: - Guided setup: auto-select after download

    /// Pure decision: which model name (if any) to activate after a download.
    /// Returns the downloaded name ONLY when it is now usable AND there is no
    /// already-usable current model (don't hijack a working setup). nil = no-op.
    nonisolated static func shouldAutoSelect(
        currentName: String?,
        currentUsable: Bool,
        downloadedName: String,
        usableNames: [String]
    ) -> String? {
        if currentName != nil && currentUsable { return nil }
        return usableNames.contains(downloadedName) ? downloadedName : nil
    }

    /// Called when a provider reports a successful download. Activates the
    /// downloaded model only into an empty/broken selection.
    func autoSelectAfterDownload(_ downloadedName: String) {
        refreshAllAvailableModels()
        let usable = usableModels
        let usableNames = usable.map { $0.name }
        let currentUsable = currentTranscriptionModel.map { c in usableNames.contains(c.name) } ?? false

        guard let pick = Self.shouldAutoSelect(
            currentName: currentTranscriptionModel?.name,
            currentUsable: currentUsable,
            downloadedName: downloadedName,
            usableNames: usableNames
        ) else { return }

        if let model = usable.first(where: { $0.name == pick }) {
            setDefaultTranscriptionModel(model)
        }
    }

    // MARK: - Guided setup: onboarding download request

    /// Resolve the onboarding-selected model id and trigger its provider's
    /// download if it isn't already usable. On completion the `onModelDownloaded`
    /// path auto-selects it. If already usable, just ensure it's the default.
    func handleRequestModelDownload(_ modelId: String) {
        guard let model = allAvailableModels.first(where: { $0.name == modelId }) else { return }

        if usableModels.contains(where: { $0.name == modelId }) {
            if currentTranscriptionModel?.name != modelId {
                setDefaultTranscriptionModel(model)
            }
            return
        }

        switch model.provider {
        case .whisper:
            if let whisperModel = model as? WhisperModel {
                Task { await whisperModelManager?.downloadModel(whisperModel) }
            }
        case .fluidAudio:
            if let fluidAudioModel = model as? FluidAudioModel {
                Task { await fluidAudioModelManager?.downloadFluidAudioModel(fluidAudioModel) }
            }
        case .nativeApple:
            break
        default:
            break
        }
    }

    // MARK: - Clear current model

    func clearCurrentTranscriptionModel() {
        currentTranscriptionModel = nil
        UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
    }

    // MARK: - Handle model deletion callback

    /// Called by WhisperModelManager.onModelDeleted or FluidAudioModelManager.onModelDeleted.
    func handleModelDeleted(_ modelName: String) {
        if currentTranscriptionModel?.name == modelName {
            currentTranscriptionModel = nil
            UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
            whisperModelManager?.loadedWhisperModel = nil
            whisperModelManager?.isModelLoaded = false
            UserDefaults.standard.removeObject(forKey: "CurrentModel")
        }
        refreshAllAvailableModels()
    }
}
