import Foundation
import os
import Zip
import SwiftUI
import Atomics

extension WhisperModelManager {
    // MARK: - Model Download & Management

    func pauseDownload(_ model: WhisperModel) {
        guard isDownloading(model) else { return }
        pausedModels.insert(model.name)
        for (key, task) in activeDownloadTasks where key.hasPrefix(model.name) {
            task.cancel { [weak self] data in
                Task { @MainActor in
                    if let data {
                        self?.resumeData[key] = data
                    }
                }
            }
        }
        downloadTasks[model.name]?.cancel()
        downloadTasks.removeValue(forKey: model.name)
    }

    func resumeDownload(_ model: WhisperModel) {
        guard pausedModels.contains(model.name) else { return }
        pausedModels.remove(model.name)
        Task {
            await downloadModel(model)
        }
    }

    func cancelDownload(_ model: WhisperModel) {
        pausedModels.remove(model.name)
        downloadTasks[model.name]?.cancel()
        downloadTasks.removeValue(forKey: model.name)
        for (key, task) in activeDownloadTasks where key.hasPrefix(model.name) {
            task.cancel()
        }
        activeDownloadTasks.removeValue(forKey: model.name + "_main")
        activeDownloadTasks.removeValue(forKey: model.name + "_coreml")
        resumeData.removeValue(forKey: model.name + "_main")
        resumeData.removeValue(forKey: model.name + "_coreml")
        downloadProgress.removeValue(forKey: model.name + "_main")
        downloadProgress.removeValue(forKey: model.name + "_coreml")
        downloadErrors.removeValue(forKey: model.name)

        let destinationURL = modelsDirectory.appendingPathComponent(model.filename)
        try? FileManager.default.removeItem(at: destinationURL)
        let zipPath = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc.zip")
        try? FileManager.default.removeItem(at: zipPath)
        let coreMLDestination = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc")
        try? FileManager.default.removeItem(at: coreMLDestination)
    }

    private func downloadFileWithProgress(from url: URL, progressKey: String) async throws -> Data {
        let destinationURL = modelsDirectory.appendingPathComponent(UUID().uuidString)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let finished = ManagedAtomic(false)

            func finishOnce(_ result: Result<Data, Error>) {
                if finished.exchange(true, ordering: .acquiring) == false {
                    continuation.resume(with: result)
                }
            }

            let resume = self.resumeData.removeValue(forKey: progressKey)
            let task: URLSessionDownloadTask
            let completion: (URL?, URLResponse?, Error?) -> Void = { [weak self] tempURL, response, error in
                Task { @MainActor in
                    self?.activeDownloadTasks.removeValue(forKey: progressKey)
                }
                if let error = error {
                    try? FileManager.default.removeItem(at: destinationURL)
                    finishOnce(.failure(error))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let tempURL = tempURL else {
                    try? FileManager.default.removeItem(at: destinationURL)
                    finishOnce(.failure(URLError(.badServerResponse)))
                    return
                }

                do {
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    let data = try Data(contentsOf: destinationURL, options: .mappedIfSafe)
                    finishOnce(.success(data))
                    try? FileManager.default.removeItem(at: destinationURL)
                } catch {
                    finishOnce(.failure(error))
                }
            }

            if let resume = resume {
                task = URLSession.shared.downloadTask(withResumeData: resume, completionHandler: completion)
            } else {
                task = URLSession.shared.downloadTask(with: url, completionHandler: completion)
            }
            self.activeDownloadTasks[progressKey] = task
            task.resume()

            var lastUpdateTime = Date()
            var lastProgressValue: Double = self.downloadProgress[progressKey] ?? 0

            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let currentTime = Date()
                let timeSinceLastUpdate = currentTime.timeIntervalSince(lastUpdateTime)
                let currentProgress = round(progress.fractionCompleted * 100) / 100

                if timeSinceLastUpdate >= 0.5 && abs(currentProgress - lastProgressValue) >= 0.01 {
                    lastUpdateTime = currentTime
                    lastProgressValue = currentProgress

                    DispatchQueue.main.async {
                        self.downloadProgress[progressKey] = currentProgress
                    }
                }
            }

            Task {
                await withTaskCancellationHandler {
                    observation.invalidate()
                    task.cancel()
                    try? FileManager.default.removeItem(at: destinationURL)
                    if finished.exchange(true, ordering: .acquiring) == false {
                        continuation.resume(throwing: CancellationError())
                    }
                } operation: {
                    await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                }
            }
        }
    }

    func downloadModel(_ model: WhisperModel) async {
        guard !availableModels.contains(where: { $0.name == model.name }),
              downloadTasks[model.name] == nil else { return }
        guard let url = URL(string: model.downloadURL) else { return }
        if downloadProgress[model.name + "_main"] == nil && downloadProgress[model.name + "_coreml"] == nil {
            downloadProgress[model.name + "_main"] = 0
        }
        downloadErrors.removeValue(forKey: model.name)
        pausedModels.remove(model.name)

        let task = Task {
            await performModelDownload(model, url)
            self.downloadTasks.removeValue(forKey: model.name)
        }
        downloadTasks[model.name] = task
        await task.value
    }

    private func performModelDownload(_ model: WhisperModel, _ url: URL) async {
        do {
            var whisperModel = try await downloadMainModel(model, from: url)

            if let coreMLZipURL = whisperModel.coreMLZipDownloadURL,
               let coreMLURL = URL(string: coreMLZipURL) {
                whisperModel = try await downloadAndSetupCoreMLModel(for: whisperModel, from: coreMLURL)
            }

            availableModels.append(whisperModel)
            self.downloadProgress.removeValue(forKey: model.name + "_main")
            self.downloadProgress.removeValue(forKey: model.name + "_coreml")

            onModelsChanged?()
            onModelDownloaded?(model.name)

            if shouldWarmup(model) {
                WhisperModelWarmupCoordinator.shared.scheduleWarmup(for: model, whisperModelManager: self)
            }
        } catch {
            handleModelDownloadError(model, error)
        }
    }

    private func downloadMainModel(_ model: WhisperModel, from url: URL) async throws -> WhisperModelFile {
        let destinationURL = modelsDirectory.appendingPathComponent(model.filename)
        if FileManager.default.fileExists(atPath: destinationURL.path) && resumeData[model.name + "_main"] == nil {
            return WhisperModelFile(name: model.name, url: destinationURL)
        }
        let progressKeyMain = model.name + "_main"
        let data = try await downloadFileWithProgress(from: url, progressKey: progressKeyMain)
        try data.write(to: destinationURL)

        return WhisperModelFile(name: model.name, url: destinationURL)
    }

    private func downloadAndSetupCoreMLModel(for model: WhisperModelFile, from url: URL) async throws -> WhisperModelFile {
        let progressKeyCoreML = model.name + "_coreml"
        let coreMLData = try await downloadFileWithProgress(from: url, progressKey: progressKeyCoreML)

        let coreMLZipPath = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc.zip")
        try coreMLData.write(to: coreMLZipPath)

        return try await unzipAndSetupCoreMLModel(for: model, zipPath: coreMLZipPath, progressKey: progressKeyCoreML)
    }

    private func unzipAndSetupCoreMLModel(for model: WhisperModelFile, zipPath: URL, progressKey: String) async throws -> WhisperModelFile {
        let coreMLDestination = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc")

        try? FileManager.default.removeItem(at: coreMLDestination)
        try await unzipCoreMLFile(zipPath, to: modelsDirectory)
        return try verifyAndCleanupCoreMLFiles(model, coreMLDestination, zipPath, progressKey)
    }

    private func unzipCoreMLFile(_ zipPath: URL, to destination: URL) async throws {
        let finished = ManagedAtomic(false)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            func finishOnce(_ result: Result<Void, Error>) {
                if finished.exchange(true, ordering: .acquiring) == false {
                    continuation.resume(with: result)
                }
            }

            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try Zip.unzipFile(zipPath, destination: destination, overwrite: true, password: nil)
                finishOnce(.success(()))
            } catch {
                finishOnce(.failure(error))
            }
        }
    }

    private func verifyAndCleanupCoreMLFiles(_ model: WhisperModelFile, _ destination: URL, _ zipPath: URL, _ progressKey: String) throws -> WhisperModelFile {
        var model = model

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            try? FileManager.default.removeItem(at: zipPath)
            throw SottoEngineError.unzipFailed
        }

        try? FileManager.default.removeItem(at: zipPath)
        model.coreMLEncoderURL = destination
        self.downloadProgress.removeValue(forKey: progressKey)

        return model
    }

    private func shouldWarmup(_ model: WhisperModel) -> Bool {
        !model.name.contains("q5") && !model.name.contains("q8")
    }

    private func handleModelDownloadError(_ model: WhisperModel, _ error: Error) {
        if pausedModels.contains(model.name) {
            return
        }
        if (error as? CancellationError) != nil || (error as NSError).code == NSURLErrorCancelled {
            self.downloadProgress.removeValue(forKey: model.name + "_main")
            self.downloadProgress.removeValue(forKey: model.name + "_coreml")
            return
        }
        self.downloadProgress.removeValue(forKey: model.name + "_main")
        self.downloadProgress.removeValue(forKey: model.name + "_coreml")
        self.downloadErrors[model.name] = error.localizedDescription
    }

    func deleteModel(_ model: WhisperModelFile) async {
        do {
            try FileManager.default.removeItem(at: model.url)

            if let coreMLURL = model.coreMLEncoderURL {
                try? FileManager.default.removeItem(at: coreMLURL)
            } else {
                let coreMLDir = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc")
                if FileManager.default.fileExists(atPath: coreMLDir.path) {
                    try? FileManager.default.removeItem(at: coreMLDir)
                }
            }

            availableModels.removeAll { $0.id == model.id }

            // Notify TranscriptionModelManager to clear currentTranscriptionModel if it matches
            onModelDeleted?(model.name)
        } catch {
            logError("Error deleting model: \(model.name)", error)
        }
    }

    func unloadModel() {
        Task {
            await whisperContext?.releaseResources()
            whisperContext = nil
            isModelLoaded = false
        }
    }

    func clearDownloadedModels() async {
        for model in availableModels {
            do {
                try FileManager.default.removeItem(at: model.url)
            } catch {
                logError("Error deleting model during cleanup", error)
            }
        }
        availableModels.removeAll()
    }
}
