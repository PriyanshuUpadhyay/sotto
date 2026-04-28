import Foundation
import os

#if canImport(MLXLLM)
import HuggingFace
#endif

private let mlxRegistryLogger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MLXModelDownloader")

struct MLXModelEntry: Identifiable, Hashable {
    let id: String              // HF repo, e.g. "mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510"
    let displayName: String
    let approximateSizeGB: Double
    let notes: String

    /// Speed tier on M-series base 32 GB for typical dictation cleanup
    /// (~50-200 token output). 1...10. 9-10 = under 3s; 6-8 = 3-7s;
    /// 3-5 = 7-15s; 1-2 = exceeds 15s. Sourced from research cited in the
    /// W6 plan; refine as users surface real numbers via the WARN log
    /// hook in `MLXProvider.enhance(...)`.
    let speedRating: Int

    /// Subjective quality on instruction-following + correction tasks.
    /// 1...10. Floor 5 = "usable for cleanup"; below 5 is dropped from
    /// the curated set.
    let qualityRating: Int

    /// Expected wall-clock latency window for typical dictation cleanup.
    /// Lower bound = ideal cold-cache hit; upper bound = warm-cache miss
    /// edge. The picker row shows min-max; `MLXProvider` does NOT enforce
    /// this — it logs WARN if `total > 10.0` regardless of which model.
    let expectedLatencySeconds: ClosedRange<Double>

    /// When true, the picker row mounts an EXPERIMENTAL chip + caution
    /// caption. Reserved for entries that exceed the user's >10s reject
    /// threshold but are kept for users who want to test them.
    let isExperimental: Bool

    init(
        id: String,
        displayName: String,
        approximateSizeGB: Double,
        notes: String,
        speedRating: Int,
        qualityRating: Int,
        expectedLatencySeconds: ClosedRange<Double>,
        isExperimental: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.approximateSizeGB = approximateSizeGB
        self.notes = notes
        self.speedRating = speedRating
        self.qualityRating = qualityRating
        self.expectedLatencySeconds = expectedLatencySeconds
        self.isExperimental = isExperimental
    }
}

enum MLXModelRegistry {
    /// Curated lineup as of W10 (April 2026). Three-tier Qwen-only Apache 2.0
    /// lineup. Filtered to entries that meet the ≤10s wall-clock latency
    /// target on M-series base 32 GB for typical dictation cleanup (50-200
    /// token output). The W6-era gemma entries (e2b, e4b) were swapped out
    /// after user-reported real-world slowness; the 26B-A4B experimental
    /// tier was dropped per user direction "smaller the model, the better
    /// the speed". All entries verified loadable against the bundled
    /// `mlx-swift-lm` 3.31.3 (qwen3 + qwen3_5 model types are registered).
    /// Ratings basis: research at
    /// `docs/superpowers/research/2026-04-29-mlx-rewriting-models.md` +
    /// W6 plan at
    /// `docs/superpowers/plans/W6-mlx-quality-and-segregation.md` (struct
    /// shape) + W10 plan at
    /// `docs/superpowers/plans/W10-mlx-registry-swap.md` (current lineup).
    /// `expectedLatencySeconds` ranges are PLACEHOLDER post-merge — refine
    /// from the user's `🦾 enhance: total=…s` log capture during the
    /// sequential pre-merge test pass.
    static let curated: [MLXModelEntry] = [
        .init(
            id: "mlx-community/Qwen3-1.7B-4bit-DWQ",
            displayName: "Qwen 3 1.7B (Fastest)",
            approximateSizeGB: 1.0,
            notes: "Alibaba. Smallest curated entry. Apache 2.0. DWQ quant recovers most 4-bit perplexity loss vs plain -4bit. qwen3 type registered in mlx-swift-lm 3.31.3. Replaces gemma-4-e2b — faster on M-base 32 GB and free of PLE-quant degradation risk.",
            speedRating: 9,
            qualityRating: 6,
            expectedLatencySeconds: 1.0...3.0  // PLACEHOLDER — refine post sequential test (Task 6)
        ),
        .init(
            id: "mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510",
            displayName: "Qwen 3 4B Instruct 2507",
            approximateSizeGB: 2.3,
            notes: "Alibaba. Default mid-tier. Apache 2.0. IFEval 88.9 (vs gemma-E4B class ~70-75). Arena-Hard 43.4. DWQ-2510 quant minimizes 4-bit quality loss. qwen3 type registered in mlx-swift-lm 3.31.3.",
            speedRating: 7,
            qualityRating: 8,
            expectedLatencySeconds: 3.0...7.0  // PLACEHOLDER — refine post sequential test (Task 6)
        ),
        .init(
            id: "mlx-community/Qwen3.5-4B-MLX-4bit",
            displayName: "Qwen 3.5 4B",
            approximateSizeGB: 2.5,
            notes: "Alibaba. Same speed tier as gemma-4-e4b; terse, on-prompt outputs.",
            speedRating: 7,
            qualityRating: 6,
            expectedLatencySeconds: 3.0...7.0
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

// MARK: - Legacy migration

extension MLXModelRegistry {
    /// One-time purge of the mlx-swift 2.x cache directory. The 2.x era stored
    /// snapshots under `~/Library/Application Support/<bundle>/MLXModels/`;
    /// swift-huggingface 0.9.0 (mlx-swift-lm 3.31.3) lands them under
    /// `~/Library/Caches/huggingface/hub/` instead, leaving the legacy dir
    /// orphaned. One install was observed holding 9.8 GB stale here.
    ///
    /// Safety:
    ///   • Only the exact path returned by `MLXProvider.applicationSupportModelsRoot()`
    ///     is touched. No traversal of symlinks; no recursion outside that root.
    ///   • Every step logged via `mlxRegistryLogger` so reclaimed bytes are
    ///     auditable in Console.app.
    ///   • Caller (App init) gates this with `@AppStorage("legacyMLXDirPurged")`
    ///     so it runs at most once per install.
    static func purgeLegacyApplicationSupportModelsIfPresent() -> Bool {
        let root = MLXProvider.applicationSupportModelsRoot()
        let fm = FileManager.default

        // Defense-in-depth: the helper returns `~/` in the non-MLX `#else` arm.
        // Refuse to act on anything that isn't the expected ApplicationSupport
        // MLXModels leaf, regardless of how the caller resolved the path.
        guard root.lastPathComponent == "MLXModels",
              root.path.contains("/Application Support/") else {
            mlxRegistryLogger.error("🦾 legacy purge: refused — sentinel mismatch on \(root.path, privacy: .public)")
            return false
        }

        guard fm.fileExists(atPath: root.path) else {
            mlxRegistryLogger.notice("🦾 legacy purge: skip — root not present at \(root.path, privacy: .public)")
            return true
        }

        let contents = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        if contents.isEmpty {
            mlxRegistryLogger.notice("🦾 legacy purge: skip — root empty at \(root.path, privacy: .public)")
            return true
        }

        let sizeBytes = (try? root.directoryAllocatedSize()) ?? 0
        do {
            try fm.removeItem(at: root)
            mlxRegistryLogger.notice("🦾 legacy purge: ✅ removed \(root.path, privacy: .public) (~\(sizeBytes / 1_073_741_824, privacy: .public) GB)")
            return true
        } catch {
            mlxRegistryLogger.error("🦾 legacy purge: ❌ \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

private extension URL {
    /// Best-effort recursive byte count for logging only. Returns 0 on any
    /// enumeration error — the purge proceeds regardless.
    func directoryAllocatedSize() throws -> Int {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: self,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: keys)
            total += values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
        }
        return total
    }
}
