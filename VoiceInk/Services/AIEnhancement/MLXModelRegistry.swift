import Foundation
import os

#if canImport(MLXLLM)
import Hub
#endif

private let mlxRegistryLogger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MLXModelDownloader")

struct MLXModelEntry: Identifiable, Hashable {
    let id: String              // HF repo, e.g. "mlx-community/Qwen2.5-3B-Instruct-4bit"
    let displayName: String
    let approximateSizeGB: Double
    let notes: String
}

enum MLXModelRegistry {
    /// Curated lineup as of April 2026. Trades size vs quality across two clear
    /// tiers: ~2.5 GB "fast default" and ~14 GB "quality" picks. Update freely;
    /// mlx-community publishes new MLX-quantised variants weekly.
    static let curated: [MLXModelEntry] = [
        .init(
            id: "mlx-community/gemma-4-e4b-it-4bit",
            displayName: "Gemma 4 E4B Instruct (4-bit)",
            approximateSizeGB: 2.5,
            notes: "Google. Built for on-device. Fastest, strong instruction-following."
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

enum MLXModelDownloader {
    /// `swift-transformers` HubApi.snapshot() writes files flat into
    /// `<downloadBase>/models/<repoId>/{config.json, model.safetensors, ...}`.
    /// Presence of `config.json` is the canonical "is downloaded" signal —
    /// the .safetensors are huge, so checking that first is fast.
    static func status(for repoId: String) -> MLXModelStatus {
        let dir = repoDir(for: repoId)
        let cfg = dir.appendingPathComponent("config.json")
        let exists = FileManager.default.fileExists(atPath: cfg.path)
        mlxRegistryLogger.notice("🦾 status: repo=\(repoId, privacy: .public) dir=\(dir.path, privacy: .public) configExists=\(exists, privacy: .public)")
        return exists ? .downloaded : .notDownloaded
    }

    static func download(
        _ repoId: String,
        approximateSizeGB: Double,
        progress: @escaping (Double) -> Void
    ) async throws {
        try preflightDiskSpace(needGB: approximateSizeGB + 1.0)

        #if canImport(MLXLLM)
        let repo = Hub.Repo(id: repoId)
        let hub = MLXProvider.sharedHubApi
        mlxRegistryLogger.notice("🦾 download start: repo=\(repoId, privacy: .public) base=\(MLXProvider.applicationSupportModelsRoot().path, privacy: .public)")
        _ = try await hub.snapshot(from: repo) { (foundationProgress: Progress) in
            progress(foundationProgress.fractionCompleted)
        }
        mlxRegistryLogger.notice("🦾 download done: repo=\(repoId, privacy: .public)")
        #else
        throw NSError(domain: "MLXModelDownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Hub framework unavailable"])
        #endif
    }

    static func delete(_ repoId: String) throws {
        let dir = repoDir(for: repoId)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
            mlxRegistryLogger.notice("🦾 deleted: repo=\(repoId, privacy: .public)")
        }
    }

    private static func preflightDiskSpace(needGB: Double) throws {
        let url = MLXProvider.applicationSupportModelsRoot()
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = Double(values?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_073_741_824.0
        guard free >= needGB else {
            throw NSError(
                domain: "MLXModelDownloader",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Need ~\(String(format: "%.1f", needGB)) GB free; \(String(format: "%.1f", free)) GB available."]
            )
        }
    }

    /// Mirror swift-transformers' `localRepoLocation`:
    ///   downloadBase / repo.type.rawValue / repo.id
    /// `repo.type.rawValue` is "models" for default Repo. `repo.id` keeps its slash
    /// ("mlx-community/Qwen3.6-27B-4bit") creating a nested two-level dir.
    private static func repoDir(for repoId: String) -> URL {
        let base = MLXProvider.applicationSupportModelsRoot()
        var dir = base.appendingPathComponent("models", isDirectory: true)
        for component in repoId.split(separator: "/") {
            dir = dir.appendingPathComponent(String(component), isDirectory: true)
        }
        return dir
    }
}
