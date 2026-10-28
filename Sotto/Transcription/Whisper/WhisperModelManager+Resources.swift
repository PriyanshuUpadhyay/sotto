import Foundation
import os
import SwiftUI

extension WhisperModelManager {
    // MARK: - Resource Management

    /// Releases the WhisperContext and resets model-loaded state.
    /// Does NOT call serviceRegistry.cleanup() — that is SottoEngine's responsibility.
    func cleanupResources() async {
        logger.notice("WhisperModelManager.cleanupResources: releasing whisper context")
        await whisperContext?.releaseResources()
        whisperContext = nil
        isModelLoaded = false
        logger.notice("WhisperModelManager.cleanupResources: completed")
    }

    // MARK: - Import Local Model

    func importWhisperModel(from sourceURL: URL) async {
        guard sourceURL.pathExtension.lowercased() == "bin" else { return }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let destinationURL = modelsDirectory.appendingPathComponent("\(baseName).bin")

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            await NotificationManager.shared.showNotification(
                title: "A model named \(baseName).bin already exists",
                type: .warning,
                duration: 4.0
            )
            return
        }

        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            let newWhisperModel = WhisperModelFile(name: baseName, url: destinationURL)
            availableModels.append(newWhisperModel)

            onModelsChanged?()

            await NotificationManager.shared.showNotification(
                title: "Imported \(destinationURL.lastPathComponent)",
                type: .success,
                duration: 3.0
            )
        } catch {
            logError("Failed to import local model", error)
            await NotificationManager.shared.showNotification(
                title: "Failed to import model: \(error.localizedDescription)",
                type: .error,
                duration: 5.0
            )
        }
    }

    // MARK: - Helpers

    func logError(_ message: String, _ error: Error) {
        logger.error("❌ \(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}
