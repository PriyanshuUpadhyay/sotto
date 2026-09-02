import Foundation
import FluidAudio
import AppKit
import os

@MainActor
class FluidAudioModelManager: ObservableObject {
    @Published var parakeetDownloadStates: [String: Bool] = [:]
    @Published var downloadProgress: [String: Double] = [:]
    /// Last download failure per model name. Set when a download throws,
    /// cleared when a new attempt starts.
    @Published var downloadErrors: [String: String] = [:]

    var onModelDeleted: ((String) -> Void)?
    var onModelsChanged: (() -> Void)?

    /// Called ONLY after a successful download, passing the model name.
    /// TranscriptionModelManager uses this to auto-activate a freshly downloaded
    /// model into an empty/broken selection (guided setup).
    var onModelDownloaded: ((String) -> Void)?

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "FluidAudioModelManager")

    // Add new Fluid Audio models here when support is added.
    static let modelVersionMap: [String: AsrModelVersion] = [
        "parakeet-tdt-0.6b-v2": .v2,
        "parakeet-tdt-0.6b-v3": .v3,
        "parakeet-tdt-ctc-110m": .tdtCtc110m,
    ]

    nonisolated static func knownAsrVersion(for modelName: String) -> AsrModelVersion? {
        modelVersionMap[modelName]
    }

    /// Parakeet Unified lives in FluidAudio's UnifiedAsrManager / Streaming
    /// family (not AsrManager/AsrModelVersion); the FluidAudio-keyed paths
    /// branch on this.
    nonisolated static func isParakeetUnifiedModel(named modelName: String) -> Bool {
        modelName == "parakeet-unified-0.6b"
    }

    /// Parakeet Realtime EOU lives in FluidAudio's StreamingEouAsrManager and is
    /// streaming-only in Sotto; do not route it through AsrModelVersion.
    nonisolated static func isParakeetEouModel(named modelName: String) -> Bool {
        modelName == "parakeet-realtime-eou-120m"
    }

    /// Nemotron Speech Streaming lives in FluidAudio's StreamingNemotronAsrManager
    /// and is streaming-only in Sotto (int8, Apple-Silicon-only); do not route it
    /// through AsrModelVersion.
    nonisolated static func isNemotronStreamingModel(named modelName: String) -> Bool {
        modelName == "nemotron-streaming-en-0.6b"
    }

    /// True for the three families served by `FluidAudioStreamingManagerCache`
    /// (Unified, EOU, Nemotron) rather than a fresh manager per dictation.
    nonisolated static func isStreamingManagerCacheFamily(named modelName: String) -> Bool {
        isParakeetUnifiedModel(named: modelName)
            || isParakeetEouModel(named: modelName)
            || isNemotronStreamingModel(named: modelName)
    }

    /// App-selected chunk tier for Nemotron streaming (lowest-latency variant).
    nonisolated static let nemotronStreamingChunkSize: NemotronChunkSize = .ms560

    /// Cohere Transcribe is an experimental BATCH model loaded via FluidAudio's
    /// CoherePipeline (not AsrManager/AsrModelVersion); the FluidAudio-keyed
    /// download/cache/transcribe paths branch on this.
    nonisolated static func isCohereModel(named modelName: String) -> Bool {
        modelName == "cohere-transcribe-03-2026"
    }

    nonisolated static let parakeetUnifiedPrecision: UnifiedEncoderPrecision = .int8

    init() {}

    // MARK: - Query helpers

    func isFluidAudioModelDownloaded(named modelName: String) -> Bool {
        UserDefaults.standard.bool(forKey: parakeetDefaultsKey(for: modelName))
    }

    func isFluidAudioModelDownloaded(_ model: FluidAudioModel) -> Bool {
        isFluidAudioModelDownloaded(named: model.name)
    }

    func isFluidAudioModelDownloading(_ model: FluidAudioModel) -> Bool {
        parakeetDownloadStates[model.name] ?? false
    }

    // MARK: - Download

    func downloadFluidAudioModel(_ model: FluidAudioModel) async {
        if isFluidAudioModelDownloaded(model) {
            return
        }

        let modelName = model.name
        parakeetDownloadStates[modelName] = true
        downloadProgress[modelName] = 0.0
        downloadErrors.removeValue(forKey: modelName)

        let timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { timer in
            Task { @MainActor in
                if let currentProgress = self.downloadProgress[modelName], currentProgress < 0.9 {
                    self.downloadProgress[modelName] = currentProgress + 0.005
                }
            }
        }

        var didSucceed = false
        do {
            if FluidAudioModelManager.isParakeetUnifiedModel(named: modelName) {
                // loadModels() downloads the bundles into the FluidAudio cache
                // if missing; load both managers so streaming + batch weights
                // land, then release them — we only want them on disk.
                let streamingManager = StreamingUnifiedAsrManager(
                    encoderPrecision: FluidAudioModelManager.parakeetUnifiedPrecision
                )
                try await streamingManager.loadModels()
                await streamingManager.cleanup()

                let batchManager = UnifiedAsrManager(
                    encoderPrecision: FluidAudioModelManager.parakeetUnifiedPrecision
                )
                try await batchManager.loadModels()
                await batchManager.cleanup()
            } else if FluidAudioModelManager.isParakeetEouModel(named: modelName) {
                let manager = StreamingEouAsrManager(chunkSize: .ms160)
                try await manager.loadModels(to: FluidAudioModelManager.parakeetEouCacheRootDirectory())
                await manager.cleanup()
            } else if FluidAudioModelManager.isNemotronStreamingModel(named: modelName) {
                let manager = StreamingNemotronAsrManager(
                    requestedChunkSize: FluidAudioModelManager.nemotronStreamingChunkSize
                )
                try await manager.loadModels(to: FluidAudioModelManager.nemotronStreamingCacheRootDirectory())
                await manager.cleanup()
            } else if FluidAudioModelManager.isCohereModel(named: modelName) {
                // CoherePipeline has no manager; download the CoreML bundle into
                // the shared FluidAudio models root, then load it lazily at
                // transcribe time.
                try await ModelHub.download(
                    .cohereTranscribeCoreml,
                    to: FluidAudioModelManager.fluidAudioModelsRootDirectory())
            } else {
                guard let version = FluidAudioModelManager.knownAsrVersion(for: modelName) else {
                    throw SottoEngineError.unsupportedFluidAudioModel(modelName)
                }
                _ = try await AsrModels.downloadAndLoad(version: version)
                _ = try await VadManager()
            }
            UserDefaults.standard.set(true, forKey: parakeetDefaultsKey(for: modelName))
            downloadProgress[modelName] = 1.0
            didSucceed = true
        } catch {
            UserDefaults.standard.set(false, forKey: parakeetDefaultsKey(for: modelName))
            downloadErrors[modelName] = error.localizedDescription
            logger.error("❌ FluidAudio download failed for \(modelName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        timer.invalidate()
        parakeetDownloadStates[modelName] = false
        downloadProgress[modelName] = nil

        onModelsChanged?()
        if didSucceed {
            onModelDownloaded?(modelName)
        }
    }

    // MARK: - Delete

    func deleteFluidAudioModel(_ model: FluidAudioModel) {
        guard let cacheDirectory = cacheDirectory(for: model.name) else {
            logger.error("Unsupported FluidAudio model id for delete: \(model.name, privacy: .public)")
            return
        }

        do {
            if FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.removeItem(at: cacheDirectory)
            }
            UserDefaults.standard.set(false, forKey: parakeetDefaultsKey(for: model.name))
        } catch {
            // Silently ignore removal errors
        }

        // Notify TranscriptionModelManager to clear currentTranscriptionModel if it matches
        onModelDeleted?(model.name)
    }

    // MARK: - Finder

    func showFluidAudioModelInFinder(_ model: FluidAudioModel) {
        guard let cacheDirectory = cacheDirectory(for: model.name) else {
            logger.error("Unsupported FluidAudio model id for Finder: \(model.name, privacy: .public)")
            return
        }

        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            NSWorkspace.shared.selectFile(cacheDirectory.path, inFileViewerRootedAtPath: "")
        }
    }

    // MARK: - Private helpers

    private func parakeetDefaultsKey(for modelName: String) -> String {
        "ParakeetModelDownloaded_\(modelName)"
    }

    private func cacheDirectory(for modelName: String) -> URL? {
        if FluidAudioModelManager.isParakeetUnifiedModel(named: modelName) {
            return FluidAudioModelManager.parakeetUnifiedCacheDirectory()
        }
        if FluidAudioModelManager.isParakeetEouModel(named: modelName) {
            return FluidAudioModelManager.parakeetEouCacheDirectory()
        }
        if FluidAudioModelManager.isNemotronStreamingModel(named: modelName) {
            return FluidAudioModelManager.nemotronStreamingCacheDirectory()
        }
        if FluidAudioModelManager.isCohereModel(named: modelName) {
            return FluidAudioModelManager.cohereCacheDirectory()
        }
        guard let version = FluidAudioModelManager.knownAsrVersion(for: modelName) else {
            return nil
        }
        return parakeetCacheDirectory(for: version)
    }

    private func parakeetCacheDirectory(for version: AsrModelVersion) -> URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    // FluidAudio's Unified managers do not expose a public cache-directory
    // helper, so mirror their layout: <AppSupport>/FluidAudio/Models/<folder>.
    // Mirrors UnifiedAsrManager.swift:143-151 in FluidAudio
    // (Repo.parakeetUnified.folderName) — keep in sync on SDK bumps.
    nonisolated static func parakeetUnifiedCacheDirectory() -> URL {
        fluidAudioModelsRootDirectory()
            .appendingPathComponent(Repo.parakeetUnified.folderName, isDirectory: true)
    }

    // StreamingEouAsrManager.loadModels(to:) expects the models root and then
    // appends Repo.parakeetEou160.folderName internally.
    nonisolated static func parakeetEouCacheRootDirectory() -> URL {
        fluidAudioModelsRootDirectory()
    }

    // Mirrors StreamingEouAsrManager.loadModels(to:) for the app's delete,
    // Finder, and test paths. 160ms is the app-selected realtime default.
    nonisolated static func parakeetEouCacheDirectory() -> URL {
        parakeetEouCacheRootDirectory()
            .appendingPathComponent(Repo.parakeetEou160.folderName, isDirectory: true)
    }

    // StreamingNemotronAsrManager.loadModels(to:) expects the models root and
    // appends the chunk tier's Repo.folderName internally.
    nonisolated static func nemotronStreamingCacheRootDirectory() -> URL {
        fluidAudioModelsRootDirectory()
    }

    // Mirrors StreamingNemotronAsrManager.loadModels(to:) for the app's delete
    // and Finder paths. Keyed to `nemotronStreamingChunkSize` (the app-selected tier).
    nonisolated static func nemotronStreamingCacheDirectory() -> URL {
        nemotronStreamingCacheRootDirectory()
            .appendingPathComponent(nemotronStreamingChunkSize.repo.folderName, isDirectory: true)
    }

    // CoherePipeline exposes no cache-directory helper; ModelHub.download
    // lays the bundle out at <root>/<Repo.cohereTranscribeCoreml.folderName>
    // (== "cohere-transcribe/q8"), which is also the encoder/decoder/vocab dir.
    nonisolated static func cohereCacheDirectory() -> URL {
        fluidAudioModelsRootDirectory()
            .appendingPathComponent(Repo.cohereTranscribeCoreml.folderName, isDirectory: true)
    }

    nonisolated private static func fluidAudioModelsRootDirectory() -> URL {
        let fileManager = FileManager.default
        let root: URL
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            root = appSupport
        } else {
            root = fileManager.temporaryDirectory
        }
        return root
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }
}
