import Foundation
import os

/// Loads the Sotto ASR registry from the bundled JSON manifest.
/// Remote-fetch + on-disk cache layer was removed 2026-05-29 — the manifest
/// is now ship-with-app only. To update the model list, edit
/// `manifests/v1/transcription-models.json` and rebuild.
final class TranscriptionRegistryLoader {
    fileprivate static let logger = Logger(subsystem: "com.sotto.Sotto", category: "TranscriptionRegistryLoader")

    init() {}

    func entries() -> [TranscriptionModelEntry] {
        guard let url = try? BundledManifest.url(),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(TranscriptionModelManifest.self, from: data) else {
            Self.logger.warning("Bundled manifest unreachable or unparseable — returning empty registry")
            return []
        }
        return manifest.models
    }
}
