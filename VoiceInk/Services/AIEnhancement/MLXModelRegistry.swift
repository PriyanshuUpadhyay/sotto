import Foundation
import os

#if canImport(MLXLLM)
import HuggingFace
#endif

private let mlxRegistryLogger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MLXModelDownloader")

struct MLXModelEntry: Identifiable, Hashable {
    let id: String              // HF repo, e.g. "mlx-community/gemma-4-e4b-it-4bit"
    let displayName: String
    let approximateSizeGB: Double
    let notes: String
}

enum MLXModelRegistry {
    /// Curated lineup as of April 2026. Three tiers: ~0.7 GB "fastest" (QAT-quantized,
    /// ideal for low-latency cleanup), ~2.5 GB "fast default", and ~14 GB "quality".
    /// All entries verified loadable against the bundled `mlx-swift-lm` 3.31.3
    /// (gemma3 + gemma3_text + gemma4 + qwen3_5 model types are registered).
    static let curated: [MLXModelEntry] = [
        .init(
            id: "mlx-community/gemma-3-1b-it-qat-4bit",
            displayName: "Gemma 3 1B QAT (Fastest)",
            approximateSizeGB: 0.7,
            notes: "Google. Smallest viable. QAT (quantization-aware training) minimizes 4-bit accuracy loss. ~3-5x faster than gemma-4-e4b on M-series."
        ),
        .init(
            id: "mlx-community/gemma-4-e4b-it-4bit",
            displayName: "Gemma 4 E4B Instruct (4-bit)",
            approximateSizeGB: 2.5,
            notes: "Google. Built for on-device. Strong instruction-following, mid-tier latency."
        ),
        .init(
            id: "mlx-community/Qwen3.5-4B-MLX-4bit",
            displayName: "Qwen 3.5 4B (4-bit)",
            approximateSizeGB: 2.5,
            notes: "Alibaba. Same speed tier; terse, on-prompt outputs."
        ),
        .init(
            id: "mlx-community/gemma-4-26b-a4b-it-4bit",
            displayName: "Gemma 4 26B-A4B Instruct (4-bit, MoE)",
            approximateSizeGB: 14.0,
            notes: "Big-model quality at small-model latency (only 4B active params per pass)."
        ),
        .init(
            id: "mlx-community/Qwen3.6-27B-4bit",
            displayName: "Qwen 3.6 27B (4-bit)",
            approximateSizeGB: 14.0,
            notes: "Newest Qwen dense. Best raw quality. ~2-3s per dictation."
        ),
    ]
}

enum MLXModelStatus: Equatable {
    case notDownloaded
    case downloading(fraction: Double)
    case downloaded
    case failed(String)
}

#if canImport(MLXLLM)
enum MLXModelDownloader {
    /// `swift-huggingface` writes the snapshot under
    /// `<cache>/models--<namespace>--<name>/snapshots/<commit-hash>/{config.json, *.safetensors, ...}`
    /// and tracks the HEAD commit in a `refs/main` file. We resolve "main" via
    /// the cache; if it returns a hash AND that hash's snapshot has `config.json`,
    /// the model is fully downloaded.
    static func status(for repoId: String) -> MLXModelStatus {
        guard let repo = Repo.ID(rawValue: repoId),
              let cache = MLXProvider.sharedHubClient.cache,
              let commit = cache.resolveRevision(repo: repo, kind: .model, ref: "main"),
              let snapshotURL = try? cache.snapshotPath(repo: repo, kind: .model, commitHash: commit) else {
            mlxRegistryLogger.notice("🦾 status: repo=\(repoId, privacy: .public) not in cache")
            return .notDownloaded
        }
        let cfg = snapshotURL.appendingPathComponent("config.json")
        let exists = FileManager.default.fileExists(atPath: cfg.path)
        mlxRegistryLogger.notice("🦾 status: repo=\(repoId, privacy: .public) snapshot=\(snapshotURL.path, privacy: .public) configExists=\(exists, privacy: .public)")
        return exists ? .downloaded : .notDownloaded
    }

    static func download(
        _ repoId: String,
        approximateSizeGB: Double,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        try preflightDiskSpace(needGB: approximateSizeGB + 1.0)

        guard let repo = Repo.ID(rawValue: repoId) else {
            throw NSError(
                domain: "MLXModelDownloader",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid repo id: \(repoId). Expected 'namespace/name'."]
            )
        }
        mlxRegistryLogger.notice("🦾 download start: repo=\(repoId, privacy: .public)")
        let progressBridge: @MainActor @Sendable (Progress) -> Void = { foundationProgress in
            progress(foundationProgress.fractionCompleted)
        }
        _ = try await MLXProvider.sharedHubClient.downloadSnapshot(
            of: repo,
            revision: "main",
            progressHandler: progressBridge
        )
        mlxRegistryLogger.notice("🦾 download done: repo=\(repoId, privacy: .public)")
    }

    static func delete(_ repoId: String) throws {
        guard let repo = Repo.ID(rawValue: repoId),
              let cache = MLXProvider.sharedHubClient.cache else { return }
        let dir = cache.repoDirectory(repo: repo, kind: .model)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
            mlxRegistryLogger.notice("🦾 deleted: repo=\(repoId, privacy: .public)")
        }
    }

    /// Probes free space against the *cache volume* (where downloads land).
    /// Falls back to the legacy MLXModels root if the cache is unavailable —
    /// both live under `~/Library` for unsandboxed builds, so volume is the same.
    private static func preflightDiskSpace(needGB: Double) throws {
        let probe = MLXProvider.sharedHubClient.cache?.cacheDirectory ?? MLXProvider.applicationSupportModelsRoot()
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = Double(values?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_073_741_824.0
        guard free >= needGB else {
            throw NSError(
                domain: "MLXModelDownloader",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Need ~\(String(format: "%.1f", needGB)) GB free; \(String(format: "%.1f", free)) GB available."]
            )
        }
    }
}
#else
enum MLXModelDownloader {
    static func status(for repoId: String) -> MLXModelStatus { .failed("MLX framework unavailable") }
    static func download(
        _ repoId: String,
        approximateSizeGB: Double,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        throw NSError(
            domain: "MLXModelDownloader",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "MLX framework unavailable in this build."]
        )
    }
    static func delete(_ repoId: String) throws {}
}
#endif
