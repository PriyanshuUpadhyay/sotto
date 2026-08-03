import Foundation
import os

#if canImport(MLXLLM)
import HuggingFace
#endif

private let mlxRegistryLogger = Logger(subsystem: OSLogSubsystems.app, category: "MLXModelRegistry")

struct MLXModelEntry: Identifiable, Hashable {
    /// HuggingFace repo id, e.g. `mlx-community/Qwen3-1.7B-4bit-DWQ`.
    let id: String
    let displayName: String
}

/// The two Qwen3 candidates for the AFM-vs-MLX enhancement A/B. This is a
/// developer-facing experiment surface reached only through the hidden
/// `EnhancementProviderMLX` flag — there is no picker UI and no in-app
/// download, so weights must be side-loaded into the HuggingFace cache
/// (`huggingface-cli download <id>`) before the flag does anything.
enum MLXModelRegistry {
    static let curated: [MLXModelEntry] = [
        .init(id: "mlx-community/Qwen3-1.7B-4bit-DWQ", displayName: "Qwen 3 1.7B (DWQ)"),
        .init(id: "mlx-community/Qwen3-0.6B-4bit", displayName: "Qwen 3 0.6B"),
    ]

    /// Hidden override; defaults to the first curated entry.
    static var selectedModelId: String {
        let stored = UserDefaults.standard.string(forKey: "EnhancementMLXModelId") ?? ""
        return curated.contains { $0.id == stored } ? stored : curated[0].id
    }
}

#if canImport(MLXLLM)
enum MLXModelDownloader {
    /// Whether `repoId` is complete enough in the HuggingFace cache to load
    /// without touching the network.
    ///
    /// `config.json` alone is not sufficient evidence: the cache writes it in
    /// the first second of a multi-GB download while the safetensors blob
    /// lands minutes later, so a config-only check reports "ready" against a
    /// partial model and the loader then hangs. A partial side-load can also
    /// leave weights present but the tokenizer missing, which sends the loader
    /// back to the network instead of falling through to AFM. So this requires
    /// all four: no in-flight lock, `config.json`, a tokenizer asset, and a
    /// resolved weight blob over 1 MB.
    static func isDownloaded(_ repoId: String) -> Bool {
        guard let repo = Repo.ID(rawValue: repoId),
              let cache = MLXProvider.sharedHubClient.cache,
              let commit = cache.resolveRevision(repo: repo, kind: .model, ref: "main"),
              let snapshotURL = try? cache.snapshotPath(repo: repo, kind: .model, commitHash: commit) else {
            return false
        }
        let fm = FileManager.default

        // Locks do NOT live under the repo directory — `HubCache` mirrors the
        // repo's cache-relative path beneath `<cacheDirectory>/.locks/`. Ask
        // the cache for the path rather than rebuilding that layout here.
        let locksDir = cache.lockPath(for: cache.repoDirectory(repo: repo, kind: .model))
        if let enumerator = fm.enumerator(at: locksDir, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.pathExtension == "lock" {
                mlxRegistryLogger.notice("🦾 mlx: repo=\(repoId, privacy: .public) download in flight (lock present)")
                return false
            }
        }

        let entries = (try? fm.contentsOfDirectory(atPath: snapshotURL.path)) ?? []
        guard entries.contains("config.json") else {
            mlxRegistryLogger.notice("🦾 mlx: repo=\(repoId, privacy: .public) no config.json")
            return false
        }

        // Exactly `tokenizer.json` — nothing else substitutes. The loader this
        // routes to (`AutoTokenizer.from(modelFolder:)` via the
        // `#huggingFaceTokenizerLoader()` macro) hard-guards on that filename
        // and throws `configurationMissing`; `tokenizer_config.json` is
        // optional metadata there, and the SentencePiece `tokenizer.model` is
        // never consulted on this path — neither one makes the curated Qwen3
        // models loadable.
        guard entries.contains("tokenizer.json") else {
            mlxRegistryLogger.notice("🦾 mlx: repo=\(repoId, privacy: .public) tokenizer.json missing")
            return false
        }

        // mlx exports use either `model.safetensors` or sharded
        // `model-0000N-of-N.safetensors`. Accept either.
        guard let weightName = entries.first(where: {
            $0.hasPrefix("model") && $0.hasSuffix(".safetensors")
        }) else {
            mlxRegistryLogger.notice("🦾 mlx: repo=\(repoId, privacy: .public) no safetensors yet")
            return false
        }

        // Resolve the symlink — the cache stores the real bytes in `blobs/`.
        let resolved = snapshotURL.appendingPathComponent(weightName).resolvingSymlinksInPath()
        let blobSize = (try? resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard blobSize > 1024 * 1024 else {
            mlxRegistryLogger.notice("🦾 mlx: repo=\(repoId, privacy: .public) blob only \(blobSize, privacy: .public) bytes — mid-download")
            return false
        }
        return true
    }
}
#else
enum MLXModelDownloader {
    static func isDownloaded(_ repoId: String) -> Bool { false }
}
#endif
