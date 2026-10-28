import Foundation
import os
import Zip
import SwiftUI
import Atomics

// MARK: - Private download task delegate

private class TaskDelegate: NSObject, URLSessionTaskDelegate {
    private let continuation: CheckedContinuation<Void, Never>
    private let finished = ManagedAtomic(false)

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if finished.exchange(true, ordering: .acquiring) == false {
            continuation.resume()
        }
    }
}

// MARK: - WhisperModelManager

@MainActor
class WhisperModelManager: ObservableObject {
    @Published var availableModels: [WhisperModelFile] = []
    @Published var downloadProgress: [String: Double] = [:]
    /// Last download failure per model name. Set when a download throws,
    /// cleared when a new attempt starts.
    @Published var downloadErrors: [String: String] = [:]
    @Published var pausedModels: Set<String> = []
    @Published var whisperContext: WhisperContext?
    @Published var isModelLoaded = false
    @Published var loadedWhisperModel: WhisperModelFile?
    @Published var isModelLoading = false

    var downloadTasks: [String: Task<Void, Never>] = [:]
    var activeDownloadTasks: [String: URLSessionDownloadTask] = [:]
    var resumeData: [String: Data] = [:]

    func isDownloading(_ model: WhisperModel) -> Bool {
        (downloadProgress.keys.contains(model.name + "_main") || downloadProgress.keys.contains(model.name + "_coreml"))
        && !pausedModels.contains(model.name)
    }

    func isPaused(_ model: WhisperModel) -> Bool {
        pausedModels.contains(model.name)
    }

    let modelsDirectory: URL
    let whisperPrompt = WhisperPrompt()

    /// Called when a model is deleted, passing the model name.
    /// TranscriptionModelManager listens to clear currentTranscriptionModel if needed.
    var onModelDeleted: ((String) -> Void)?

    /// Called after a new model is added (downloaded or imported) so
    /// TranscriptionModelManager can rebuild allAvailableModels.
    var onModelsChanged: (() -> Void)?

    /// Called ONLY after a successful network download (not import), passing the
    /// downloaded model name. TranscriptionModelManager uses this to auto-activate
    /// a freshly downloaded model into an empty/broken selection (guided setup).
    var onModelDownloaded: ((String) -> Void)?

    let logger = Logger(subsystem: OSLogSubsystems.app, category: "WhisperModelManager")

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    // MARK: - Model Directory Management

    func createModelsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logError("Error creating models directory", error)
        }
    }

    func loadAvailableModels() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
            availableModels = fileURLs.compactMap { url in
                guard url.pathExtension == "bin" else { return nil }
                return WhisperModelFile(name: url.deletingPathExtension().lastPathComponent, url: url)
            }
        } catch {
            logError("Error loading available models", error)
        }
    }

    // MARK: - Model Loading

    func loadModel(_ model: WhisperModelFile) async throws {
        guard whisperContext == nil else { return }

        isModelLoading = true
        defer { isModelLoading = false }

        do {
            whisperContext = try await WhisperContext.createContext(path: model.url.path)

            let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? whisperPrompt.transcriptionPrompt
            await whisperContext?.setPrompt(currentPrompt)

            isModelLoaded = true
            loadedWhisperModel = model
        } catch {
            throw SottoEngineError.modelLoadFailed
        }
    }

}

// MARK: - WhisperModelProvider

extension WhisperModelManager: WhisperModelProvider {}
