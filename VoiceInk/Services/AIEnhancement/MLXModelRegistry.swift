import Foundation
import os

#if canImport(MLXLLM)
import HuggingFace
#endif

private let mlxRegistryLogger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MLXModelDownloader")

/// W11.B detected-model row payload. A repo found in the HF cache that is
/// either NOT in `MLXModelRegistry.curated` (side-loaded via the HF CLI /
/// mlx-lm) or has been evicted from the curated lineup but still holds disk
/// weight. The picker surfaces these in a separate "Detected models" section
/// so users can `Use` or `Delete` without speed/quality curation. No latency
/// claim is made — these are uncurated.
struct DetectedMLXModel: Identifiable, Hashable {
    /// HF repo id, e.g. "mlx-community/SmolLM3-3B-4bit".
    let id: String
    /// Aggregate on-disk byte count for the repo (snapshot + blobs). 0 when
    /// scan can't size the dir (sandbox / permission issue) — UI shows "—".
    let sizeBytes: UInt64

    /// Human-readable size string: "1.7 GB" / "335 MB" / "—".
    var sizeDisplay: String {
        guard sizeBytes > 0 else { return "—" }
        let gb = Double(sizeBytes) / 1_073_741_824.0
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(sizeBytes) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }
}

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
        // W11.B additions — diversifies the lineup beyond the Qwen-only W10
        // set. License diversity (MIT, Llama Community, Apache 2.0 from IBM
        // and HuggingFaceTB) and an ULTRA-FAST 0.6B tier for sub-1s cleanup.
        // Sizes / quality numbers from R1 research at
        // `docs/superpowers/research/2026-04-29-specialized-rewrite-models.md`.
        // Latency ranges PLACEHOLDER — refine post sequential test.
        .init(
            id: "mlx-community/Qwen3-0.6B-4bit",
            displayName: "Qwen 3 0.6B (Ultra-Fast)",
            approximateSizeGB: 0.34,
            notes: "Alibaba. Ultra-fast tier. Apache 2.0. Smallest entry. Best for short-transcript cleanup; lower quality on complex prompts than 1.7B+. Doubles as the speculative-decoding draft model in W11.C.",
            speedRating: 10,
            qualityRating: 5,
            expectedLatencySeconds: 0.5...2.0
        ),
        .init(
            id: "mlx-community/Phi-3.5-mini-instruct-4bit",
            displayName: "Phi 3.5 Mini Instruct",
            approximateSizeGB: 2.15,
            notes: "Microsoft. License: MIT (more permissive than Llama Community). MMLU 69, strong on reasoning-heavy prompts.",
            speedRating: 7,
            qualityRating: 7,
            expectedLatencySeconds: 3.0...7.0
        ),
        .init(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            displayName: "Llama 3.2 3B Instruct",
            approximateSizeGB: 1.81,
            notes: "Meta. Open-Rewrite 40.1 (best-in-class for rewriting). License: Llama 3.2 Community (NOT Apache) — requires 'Built with Llama' attribution. Flag for legal review before promoting to default.",
            speedRating: 7,
            qualityRating: 8,
            expectedLatencySeconds: 3.0...7.0
        ),
        .init(
            id: "mlx-community/granite-3.3-2b-instruct-4bit",
            displayName: "Granite 3.3 2B Instruct",
            approximateSizeGB: 1.43,
            notes: "IBM. Apache 2.0. Sweet-spot 2B with strong instruction-following. Less community testing than Qwen / Llama.",
            speedRating: 8,
            qualityRating: 6,
            expectedLatencySeconds: 2.0...5.0
        ),
        .init(
            id: "mlx-community/SmolLM3-3B-4bit-DWQ",
            displayName: "SmolLM 3 3B (DWQ)",
            approximateSizeGB: 1.7,
            notes: "HuggingFaceTB. Apache 2.0. IFEval 76.7 (no-think) — best in 3B class. DWQ quant. smollm3 type registered in mlx-swift-lm 3.31.3.",
            speedRating: 7,
            qualityRating: 7,
            expectedLatencySeconds: 3.0...6.0
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
    /// Snapshot of `LLMTypeRegistry.shared` registered model types in
    /// mlx-swift-lm 3.31.3, transcribed from
    /// `Libraries/MLXLLM/LLMModelFactory.swift`. Used to filter detected
    /// repos in the HF cache to ones we can actually load. Keep this in
    /// sync if mlx-swift-lm is bumped — surfacing a repo whose type isn't
    /// registered would mislead the user into picking a model that fails
    /// at load. R1 research §3.7 + reference list at
    /// `docs/superpowers/research/2026-04-29-specialized-rewrite-models.md`.
    private static let registeredMLXLLMModelTypes: Set<String> = [
        "mistral", "mistral3",
        "llama",
        "phi", "phi3", "phimoe",
        "gemma", "gemma2", "gemma3", "gemma3_text", "gemma3n",
        "gemma4", "gemma4_text",
        "qwen2", "qwen3", "qwen3_moe", "qwen3_next",
        "qwen3_5", "qwen3_5_moe", "qwen3_5_text",
        "minicpm", "starcoder2", "cohere", "openelm", "internlm2",
        "deepseek_v3",
        "granite", "granitemoehybrid",
        "mimo", "mimo_v2_flash", "minimax",
        "glm4", "glm4_moe", "glm4_moe_lite",
        "acereason", "falcon_h1", "bitnet",
        "smollm3", "ernie4_5", "lfm2",
        "baichuan_m1", "exaone4", "gpt_oss",
        "lille-130m",
        "olmoe", "olmo2", "olmo3",
        "bailing_moe", "lfm2_moe", "nanochat", "nemotron_h",
        "afmoe", "jamba_3b", "apertus",
    ]

    /// Repo-id strings of all locally cached models that mlx-swift-lm 3.31.3
    /// can load. Scans `cache.cacheDirectory` for `models--<ns>--<name>`
    /// directories whose snapshot `config.json` declares a `model_type`
    /// registered in `LLMTypeRegistry.shared`. Used by the picker UI to
    /// surface side-loaded repos (e.g. ones the user pulled via mlx-lm
    /// from the command line) and curated entries that have been removed
    /// in a later registry refresh but still hold disk weight.
    ///
    /// Sorted alphabetically. Returns `[]` when the cache directory can't
    /// be enumerated (sandbox / permission issue) or when no eligible repo
    /// is found. Curated-list duplicates are NOT filtered here — the picker
    /// view dedupes against `MLXModelRegistry.curated` so this helper stays
    /// schema-agnostic.
    static func detectInstalledModels() -> [String] {
        detectInstalledModelsDetailed().map(\.id)
    }

    /// `detectInstalledModels` plus on-disk byte counts. Used by the picker
    /// UI to render a size column without a second filesystem walk.
    static func detectInstalledModelsDetailed() -> [DetectedMLXModel] {
        guard let cache = MLXProvider.sharedHubClient.cache else { return [] }
        let fm = FileManager.default
        let root = cache.cacheDirectory
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            mlxRegistryLogger.notice("🦾 detect: cache enumerate failed at \(root.path, privacy: .public)")
            return []
        }

        var results: [DetectedMLXModel] = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let dirName = url.lastPathComponent
            // HF Python-compat layout: `models--<namespace>--<name>`. The
            // intermediate `--` is the kind/ns separator; the second `--`
            // separates ns from name. HF repo names don't carry `--` in
            // practice (single dashes only), so a first-occurrence split is
            // both correct and defensive against mangled directory names.
            guard dirName.hasPrefix("models--") else { continue }
            let stripped = String(dirName.dropFirst("models--".count))
            guard let sep = stripped.range(of: "--") else { continue }
            let namespace = String(stripped[stripped.startIndex..<sep.lowerBound])
            let repoName = String(stripped[sep.upperBound..<stripped.endIndex])
            guard !namespace.isEmpty, !repoName.isEmpty else { continue }
            let repoId = "\(namespace)/\(repoName)"
            guard let repo = Repo.ID(rawValue: repoId),
                  let commit = cache.resolveRevision(repo: repo, kind: .model, ref: "main"),
                  let snapshotURL = try? cache.snapshotPath(repo: repo, kind: .model, commitHash: commit) else {
                continue
            }
            let cfgURL = snapshotURL.appendingPathComponent("config.json")
            guard fm.fileExists(atPath: cfgURL.path),
                  let data = try? Data(contentsOf: cfgURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelType = json["model_type"] as? String,
                  Self.registeredMLXLLMModelTypes.contains(modelType) else {
                continue
            }
            let bytes = (try? url.directoryAllocatedSize()) ?? 0
            results.append(DetectedMLXModel(id: repoId, sizeBytes: UInt64(max(bytes, 0))))
        }
        results.sort { $0.id < $1.id }
        mlxRegistryLogger.notice("🦾 detect: found \(results.count, privacy: .public) eligible cached repos")
        return results
    }

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
    static func detectInstalledModels() -> [String] { [] }
    static func detectInstalledModelsDetailed() -> [DetectedMLXModel] { [] }
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
