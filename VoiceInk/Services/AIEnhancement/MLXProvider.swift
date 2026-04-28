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
        let approxInputTokens = userPrompt.count / 4
        let dynamicMaxTokens = max(192, min(768, approxInputTokens * 3))

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

            let parameters = GenerateParameters(
                maxTokens: dynamicMaxTokens,
                temperature: 0.1,
                topP: 0.9
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
        #else
        throw ProviderError.frameworkUnavailable
        #endif
    }

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
