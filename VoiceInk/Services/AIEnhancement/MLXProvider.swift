import Foundation
import os

#if canImport(MLXLLM)
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers
#endif

/// On-device LLM provider using mlx-swift-lm. Loads MLX-quantised HuggingFace
/// models lazily; idle-evicts after `idleEvictSeconds` to free RAM. All state
/// is actor-isolated; cancellation honoured at load and generate boundaries.
actor MLXProvider {

    enum ProviderError: Error, LocalizedError {
        case noModelSelected
        case modelNotDownloaded(String)
        case modelLoadFailed(String)
        case generationFailed(String)
        case frameworkUnavailable

        var errorDescription: String? {
            switch self {
            case .noModelSelected:
                return "No MLX model selected. Pick one in Settings → AI Enhancement → MLX."
            case .modelNotDownloaded(let id):
                return "Model not downloaded: \(id). Download it from the MLX picker first."
            case .modelLoadFailed(let why):
                return "MLX model load failed: \(why)"
            case .generationFailed(let why):
                return "MLX generation failed: \(why)"
            case .frameworkUnavailable:
                return "mlx-swift framework not available in this build."
            }
        }
    }

    private let modelId: String
    private let idleEvictSeconds: TimeInterval

    #if canImport(MLXLLM)
    private var modelContainer: ModelContainer?
    #endif
    private var lastUsedAt: Date?
    private var evictTask: Task<Void, Never>?

    init(modelId: String, idleEvictSeconds: TimeInterval = 600) {
        self.modelId = modelId
        self.idleEvictSeconds = idleEvictSeconds
    }

    deinit {
        evictTask?.cancel()
    }

    func enhance(systemPrompt: String, userPrompt: String) async throws -> String {
        #if canImport(MLXLLM)
        // W11.A5: wall-clock timeout reuses the existing user-set
        // `EnhancementTimeoutSeconds` (default 7s). Caps cold + warm + rambling
        // outputs the same way remote-API providers are already capped at
        // AIEnhancementService.swift:74. UserDefaults read is thread-safe inside
        // an actor. Plan §Migration policy #7-#8.
        let storedTimeout = UserDefaults.standard.integer(forKey: "EnhancementTimeoutSeconds")
        let effectiveTimeout: TimeInterval = storedTimeout > 0 ? TimeInterval(storedTimeout) : 7

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [systemPrompt, userPrompt] in
                try await self.runEnhance(systemPrompt: systemPrompt, userPrompt: userPrompt)
            }
            group.addTask { [effectiveTimeout, modelId] in
                try await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                Self.logger.warning("🦾 enhance: TIMEOUT after \(effectiveTimeout, format: .fixed(precision: 1), privacy: .public)s — cancelling generation for model=\(modelId, privacy: .public)")
                throw ProviderError.generationFailed("Timed out after \(Int(effectiveTimeout))s")
            }
            do {
                guard let result = try await group.next() else {
                    group.cancelAll()
                    throw ProviderError.generationFailed("Enhancement task group returned no result")
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
        #else
        throw ProviderError.frameworkUnavailable
        #endif
    }

    #if canImport(MLXLLM)
    private func runEnhance(systemPrompt: String, userPrompt: String) async throws -> String {
        guard !modelId.isEmpty else { throw ProviderError.noModelSelected }
        try Task.checkCancellation()

        let totalStart = Date()
        let loadStart = Date()
        let container = try await loadModel()
        let loadElapsed = Date().timeIntervalSince(loadStart)
        if loadElapsed > 0.05 {
            Self.logger.notice("🦾 enhance: model-load took \(loadElapsed, format: .fixed(precision: 2), privacy: .public)s (cold)")
        }

        self.lastUsedAt = Date()
        self.scheduleEvictionCheck()

        // For cleanup-style enhancement, output should be roughly the same length as
        // input. Cap tokens at ~3x input length (chars/4 ≈ token estimate) plus a
        // floor so very short transcripts still have headroom. Clamps the worst case
        // where small models ramble and burn the full 1024-token window.
        // W11.A7: floor 192→96 for very-short transcripts (<30 chars); ceiling
        // 768→512 universally. Real cleanup output is 80-200 tokens; 512 is still
        // 2.5× expected. See plan docs/superpowers/plans/W11A-pipeline-fixes.md
        // §Migration policy #10.
        let approxInputTokens = userPrompt.count / 4
        let floor = userPrompt.count < 30 ? 96 : 192
        let dynamicMaxTokens = max(floor, min(512, approxInputTokens * 3))

        do {
            try Task.checkCancellation()

            let prepStart = Date()
            let messages: [Chat.Message] = [
                .system(systemPrompt),
                .user(userPrompt),
            ]
            let userInput = UserInput(chat: messages)
            let input = try await container.prepare(input: userInput)
            let prepElapsed = Date().timeIntervalSince(prepStart)

            // W11.A4: temperature=0.0 routes to ArgMaxSampler; topP omitted (ignored
            // at temp=0). Quality-neutral on cleanup task; cuts 5-15ms per 100 tokens
            // and is forward-compatible with W11.C speculative decoding.
            let parameters = GenerateParameters(
                maxTokens: dynamicMaxTokens,
                temperature: 0.0
            )
            Self.logger.notice("🦾 enhance: prep=\(prepElapsed, format: .fixed(precision: 2), privacy: .public)s maxTokens=\(dynamicMaxTokens, privacy: .public) input=\(userPrompt.count, privacy: .public)c")

            var output = ""
            var firstChunkAt: TimeInterval?
            var chunkCount = 0
            let genStart = Date()

            let stream = try await container.generate(
                input: input,
                parameters: parameters
            )
            for await item in stream {
                if Task.isCancelled { break }
                switch item {
                case .chunk(let chunk):
                    if firstChunkAt == nil {
                        firstChunkAt = Date().timeIntervalSince(genStart)
                    }
                    output += chunk
                    chunkCount += 1
                case .info, .toolCall:
                    break
                @unknown default:
                    break
                }
            }
            let genElapsed = Date().timeIntervalSince(genStart)
            let ttft = firstChunkAt ?? genElapsed
            let tokenRate = genElapsed > 0 ? Double(chunkCount) / genElapsed : 0
            Self.logger.notice("🦾 enhance: gen=\(genElapsed, format: .fixed(precision: 2), privacy: .public)s ttft=\(ttft, format: .fixed(precision: 2), privacy: .public)s tokens≈\(chunkCount, privacy: .public) (\(tokenRate, format: .fixed(precision: 1), privacy: .public) tok/s) output=\(output.count, privacy: .public)c")

            try Task.checkCancellation()
            let totalElapsed = Date().timeIntervalSince(totalStart)
            Self.logger.notice("🦾 enhance: total=\(totalElapsed, format: .fixed(precision: 2), privacy: .public)s")
            if totalElapsed > 10.0 {
                Self.logger.warning("🦾 enhance: WARN total=\(totalElapsed, format: .fixed(precision: 2), privacy: .public)s exceeds 10s ceiling for model=\(self.modelId, privacy: .public)")
            }
            return output
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("🦾 MLX generate failed: \(error.localizedDescription, privacy: .public)")
            throw ProviderError.generationFailed("\(modelId): \(error.localizedDescription)")
        }
    }
    #endif

    /// Drop the loaded model and cancel pending eviction. Called when the user
    /// switches to a different MLX model or away from MLX entirely.
    func reset() {
        evictTask?.cancel()
        evictTask = nil
        #if canImport(MLXLLM)
        modelContainer = nil
        #endif
        lastUsedAt = nil
    }

    /// W11.A1: load weights into memory without running enhance. Idempotent —
    /// a second call when warm is a cheap actor-state check on the cached
    /// `modelContainer`. Used by the prewarm hook + recording-start fire-and-
    /// forget warm path so first-enhance-after-idle skips cold-load.
    func warm() async throws {
        #if canImport(MLXLLM)
        guard !modelId.isEmpty else { throw ProviderError.noModelSelected }
        _ = try await loadModel()
        self.lastUsedAt = Date()
        self.scheduleEvictionCheck()
        #else
        throw ProviderError.frameworkUnavailable
        #endif
    }

    // MARK: - Loading

    #if canImport(MLXLLM)
    private func loadModel() async throws -> ModelContainer {
        if let existing = modelContainer { return existing }
        try Task.checkCancellation()

        let configuration = ModelConfiguration(id: modelId)
        Self.logger.notice("🦾 loadModel: id=\(self.modelId, privacy: .public)")

        do {
            let loaded = try await loadModelContainer(
                from: #hubDownloader(MLXProvider.sharedHubClient),
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration
            ) { progress in
                #if DEBUG
                MLXProvider.logger.notice("🦾 load progress: \(Int(progress.fractionCompleted * 100), privacy: .public)%")
                #endif
            }
            try Task.checkCancellation()
            self.modelContainer = loaded
            Self.logger.notice("🦾 loadModel: ✅ loaded \(self.modelId, privacy: .public)")
            return loaded
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("🦾 loadModel: ❌ \(error.localizedDescription, privacy: .public)")
            throw ProviderError.modelLoadFailed("\(modelId): \(error.localizedDescription)")
        }
    }

    /// Shared `HubClient` for downloads. `swift-huggingface` auto-detects cache
    /// location (Library/Caches/huggingface/hub for sandboxed apps), which is
    /// fine for VoiceInk — token auth and endpoint default to public HF.
    nonisolated static let sharedHubClient: HubClient = HubClient()

    /// Legacy MLX cache root from the 2.x mlx-swift-examples era. Retained for
    /// the MLX picker UI's status check + cleanup hooks; downloads under
    /// `mlx-swift-lm` 3.x land in `swift-huggingface`'s Python-compatible
    /// `~/Library/Caches/huggingface/hub` instead.
    nonisolated static func applicationSupportModelsRoot() -> URL {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let bundle = Bundle.main.bundleIdentifier ?? "com.prakashjoshipax.voiceink"
        let target = appSupport
            .appendingPathComponent(bundle, isDirectory: true)
            .appendingPathComponent("MLXModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }
    #else
    // Stub for non-MLX builds — unused but keeps the symbol resolvable.
    nonisolated static func applicationSupportModelsRoot() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }
    #endif

    nonisolated static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MLXProvider")

    // MARK: - Idle eviction

    private func scheduleEvictionCheck() {
        evictTask?.cancel()
        let timeout = self.idleEvictSeconds
        evictTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if Task.isCancelled { return }
            await self?.evictIfIdle()
        }
    }

    private func evictIfIdle() {
        guard let last = lastUsedAt,
              Date().timeIntervalSince(last) >= idleEvictSeconds else { return }
        #if canImport(MLXLLM)
        modelContainer = nil
        Self.logger.notice("🦾 evicted \(self.modelId, privacy: .public) after idle")
        #endif
    }
}
