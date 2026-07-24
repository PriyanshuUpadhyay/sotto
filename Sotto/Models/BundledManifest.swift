import Foundation

enum BundledManifest {
    /// URL to the build-time bundled `transcription-models.bundled.json`.
    /// Used by `TranscriptionRegistryLoader` (M02) as the final fallback when
    /// no fresh fetched cache is available.
    static func url() throws -> URL {
        guard let url = Bundle.main.url(
            forResource: "transcription-models.bundled",
            withExtension: "json"
        ) else {
            throw NSError(
                domain: "BundledManifest", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Bundled manifest resource missing from app bundle"]
            )
        }
        return url
    }
}
