import Foundation
import os

#if canImport(MLXLLM)
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
// Referenced by the `#huggingFaceTokenizerLoader()` macro expansion.
import Tokenizers
#endif

/// On-device LLM provider using mlx-swift-lm. Loads MLX-quantised HuggingFace
/// models lazily; idle-evicts after `idleEvictSeconds` to free RAM. All state
/// is actor-isolated; cancellation honoured at load and generate boundaries.
///
/// Reached only via the hidden `EnhancementProviderMLX` flag — AFM is the
/// shipping enhancement path. Emits rows to the same
/// `EnhancementTimingLogger` as AFM (with the MLX repo id as `modelId`) so
/// the two paths are directly comparable in one CSV.
actor MLXProvider {

    enum ProviderError: Error, LocalizedError {
        case noModelSelected
        case modelLoadFailed(String)
        case generationFailed(String)
        case frameworkUnavailable
        case timedOut(seconds: TimeInterval)
        /// Generation stopped on the token cap rather than an EOS token, so
        /// the text is a prefix of the real answer. Never returned as success:
        /// a truncated cleanup reads as a plausible complete one (the sanity
        /// guard sees a grounded prefix and passes it), so the only safe
        /// outcome is to fail and let the raw transcript through.
        case outputTruncated(maxTokens: Int)

        var errorDescription: String? {
            switch self {
            case .noModelSelected:
                return "No MLX model selected."
            case .modelLoadFailed(let why):
                return "MLX model load failed: \(why)"
            case .generationFailed(let why):
                return "MLX generation failed: \(why)"
            case .frameworkUnavailable:
                return "mlx-swift framework not available in this build."
            case .timedOut(let seconds):
                return "MLX enhancement timed out after \(Int(seconds))s."
            case .outputTruncated(let maxTokens):
                return "MLX output hit the \(maxTokens)-token cap and was truncated."
            }
        }
    }

    #if canImport(MLXLLM)
    /// One call's generation result. Returned by value rather than stashed on
    /// the actor: this provider is shared, and a file-import enhance can
    /// interleave with a live dictation's, so per-call timings held as actor
    /// properties get overwritten by whichever call last suspended.
    private struct GenerationOutcome: Sendable {
        let output: String
        let prepSeconds: TimeInterval
        let ttftSeconds: TimeInterval
        let genSeconds: TimeInterval
    }
    #endif

    let modelId: String
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

    func enhance(
        systemPrompt: String,
        userPrompt: String,
        transcriptChars: Int,
        callKind: EnhancementTimingLogger.CallKind
    ) async throws -> String {
        #if canImport(MLXLLM)
        // Wall-clock timeout reuses the user-set `EnhancementTimeoutSeconds`,
        // capping cold loads and rambling outputs alike.
        let storedTimeout = UserDefaults.standard.integer(forKey: "EnhancementTimeoutSeconds")
        let effectiveTimeout: TimeInterval = storedTimeout > 0 ? TimeInterval(storedTimeout) : 15

        let startedAt = Date()
        let modelIdSnapshot = self.modelId
        let promptChars = systemPrompt.count + userPrompt.count

        // `result` is nil on every failure branch: a call that timed out or
        // errored has no complete set of timings to report, and reading a
        // partial set off the actor is exactly the cross-call bleed this
        // signature avoids. `totalSeconds` still bounds those rows.
        func recordOutcome(
            _ outcome: EnhancementTimingLogger.Outcome,
            _ result: GenerationOutcome?
        ) async {
            let total = Date().timeIntervalSince(startedAt)
            await EnhancementTimingLogger.shared.record(
                modelId: modelIdSnapshot,
                promptMode: .standard,
                transcriptChars: transcriptChars,
                promptChars: promptChars,
                callKind: callKind,
                // MLX has no warm-session prefill to age — `warm(source:)`
                // only pages weights, which `prepSeconds` already reflects.
                warmAgeSeconds: nil,
                outputChars: result?.output.count ?? 0,
                prepSeconds: result?.prepSeconds,
                ttftSeconds: result?.ttftSeconds,
                genSeconds: result?.genSeconds,
                totalSeconds: total,
                startedAt: startedAt,
                outcome: outcome,
                sessionReused: false
            )
        }

        do {
            let result = try await withThrowingTaskGroup(of: GenerationOutcome.self) { group in
                group.addTask { [systemPrompt, userPrompt] in
                    try await self.runEnhance(systemPrompt: systemPrompt, userPrompt: userPrompt)
                }
                group.addTask { [effectiveTimeout] in
                    try await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                    Self.logger.warning("🦾 mlx: timeout fired after \(effectiveTimeout, format: .fixed(precision: 1), privacy: .public)s")
                    throw ProviderError.timedOut(seconds: effectiveTimeout)
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
            await recordOutcome(.success, result)
            return result.output
        } catch is CancellationError {
            await recordOutcome(.cancelled, nil)
            throw CancellationError()
        } catch let error as ProviderError {
            // `group.next()` rethrows whichever child finished first, so a
            // fired timeout surfaces as `.timedOut` here directly — no shared
            // "did the timeout fire" flag to be clobbered by a concurrent call.
            if case .timedOut = error {
                await recordOutcome(.timedOut, nil)
            } else {
                await recordOutcome(.error, nil)
            }
            throw error
        } catch {
            await recordOutcome(.error, nil)
            throw error
        }
        #else
        throw ProviderError.frameworkUnavailable
        #endif
    }

    #if canImport(MLXLLM)
    private func runEnhance(systemPrompt: String, userPrompt: String) async throws -> GenerationOutcome {
        guard !modelId.isEmpty else { throw ProviderError.noModelSelected }
        try Task.checkCancellation()

        let loadStart = Date()
        let container = try await loadModel()
        let loadElapsed = Date().timeIntervalSince(loadStart)
        if loadElapsed > 0.05 {
            Self.logger.notice("🦾 mlx: model-load took \(loadElapsed, format: .fixed(precision: 2), privacy: .public)s (cold)")
        }

        self.lastUsedAt = Date()
        self.scheduleEvictionCheck()

        // Cleanup output is roughly input-length, so cap tokens at ~3x the
        // input estimate (chars/4 ≈ tokens) with a floor for very short
        // transcripts. Clamps the worst case where small models ramble and
        // burn the whole window.
        let approxInputTokens = userPrompt.count / 4
        let floor = userPrompt.count < 30 ? 96 : 192
        let dynamicMaxTokens = max(floor, min(512, approxInputTokens * 3))

        // temperature=0 routes to ArgMaxSampler — cleanup is a deterministic
        // transform, so sampling only adds variance. Matches the AFM path's
        // greedy setting.
        let parameters = GenerateParameters(maxTokens: dynamicMaxTokens, temperature: 0.0)

        do {
            try Task.checkCancellation()

            let prepStart = Date()
            let userInput = UserInput(chat: [.system(systemPrompt), .user(userPrompt)])
            let input = try await container.prepare(input: userInput)
            let prepElapsed = Date().timeIntervalSince(prepStart)

            var output = ""
            var firstChunkAt: TimeInterval?
            var chunkCount = 0
            var stopReason: GenerateStopReason?
            let genStart = Date()

            let stream = try await container.generate(input: input, parameters: parameters)
            for await item in stream {
                if Task.isCancelled { break }
                switch item {
                case .chunk(let chunk):
                    if firstChunkAt == nil {
                        firstChunkAt = Date().timeIntervalSince(genStart)
                    }
                    output += chunk
                    chunkCount += 1
                case .info(let info):
                    stopReason = info.stopReason
                case .toolCall:
                    break
                @unknown default:
                    break
                }
            }
            try Task.checkCancellation()

            let genElapsed = Date().timeIntervalSince(genStart)
            let ttft = firstChunkAt ?? genElapsed
            let tokenRate = genElapsed > 0 ? Double(chunkCount) / genElapsed : 0

            Self.logger.notice("🦾 mlx: prep=\(prepElapsed, format: .fixed(precision: 2), privacy: .public)s ttft=\(ttft, format: .fixed(precision: 2), privacy: .public)s gen=\(genElapsed, format: .fixed(precision: 2), privacy: .public)s tokens≈\(chunkCount, privacy: .public) (\(tokenRate, format: .fixed(precision: 1), privacy: .public) tok/s) output=\(output.count, privacy: .public)c stop=\(String(describing: stopReason), privacy: .public)")

            // The stream reports why it stopped, so unlike the AFM path a
            // capped response is distinguishable from a complete one. Fail
            // instead of returning the prefix — downstream treats a returned
            // string as a finished cleanup and would paste half a transcript.
            if stopReason == .length {
                throw ProviderError.outputTruncated(maxTokens: dynamicMaxTokens)
            }

            return GenerationOutcome(
                output: output,
                prepSeconds: prepElapsed,
                ttftSeconds: ttft,
                genSeconds: genElapsed
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ProviderError {
            throw error
        } catch {
            Self.logger.error("🦾 mlx: generate failed: \(error.localizedDescription, privacy: .public)")
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

    /// Load weights into memory without running enhance. Idempotent — a second
    /// call when warm is a cheap actor-state check on `modelContainer`.
    func warm(source: String) async throws {
        #if canImport(MLXLLM)
        guard !modelId.isEmpty else { throw ProviderError.noModelSelected }
        let alreadyLoaded = (modelContainer != nil)
        _ = try await loadModel()
        self.lastUsedAt = Date()
        self.scheduleEvictionCheck()
        let status = alreadyLoaded ? "alreadyLoaded" : "loaded"
        Self.logger.notice("🦾 mlx: prewarm model=\(self.modelId, privacy: .public) source=\(source, privacy: .public) status=\(status, privacy: .public)")
        #else
        throw ProviderError.frameworkUnavailable
        #endif
    }

    // MARK: - Loading

    #if canImport(MLXLLM)
    private func loadModel() async throws -> ModelContainer {
        if let existing = modelContainer { return existing }
        try Task.checkCancellation()

        Self.logger.notice("🦾 mlx: loadModel id=\(self.modelId, privacy: .public)")
        do {
            let loaded = try await loadModelContainer(
                from: #hubDownloader(MLXProvider.sharedHubClient),
                using: #huggingFaceTokenizerLoader(),
                configuration: ModelConfiguration(id: modelId)
            )
            try Task.checkCancellation()
            self.modelContainer = loaded
            Self.logger.notice("🦾 mlx: loadModel ✅ \(self.modelId, privacy: .public)")
            return loaded
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("🦾 mlx: loadModel ❌ \(error.localizedDescription, privacy: .public)")
            throw ProviderError.modelLoadFailed("\(modelId): \(error.localizedDescription)")
        }
    }

    /// Shared `HubClient` for cache lookups. `swift-huggingface` auto-detects
    /// the cache location (`~/Library/Caches/huggingface/hub`); token auth and
    /// endpoint default to public HF.
    nonisolated static let sharedHubClient: HubClient = HubClient()
    #endif

    nonisolated static let logger = Logger(subsystem: OSLogSubsystems.app, category: "MLXProvider")

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
        Self.logger.notice("🦾 mlx: evicted \(self.modelId, privacy: .public) after idle (\(Int(self.idleEvictSeconds), privacy: .public)s)")
        #endif
    }
}
