import Foundation
import os
import CryptoKit

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
        case timedOut(seconds: TimeInterval)

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
            case .timedOut(let seconds):
                return "MLX enhancement timed out after \(Int(seconds))s."
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

    // W11.D — per-call timing capture. Populated by `runEnhance` so the
    // outer `enhance(...)` can record() the timing row from any of the four
    // outcome branches (success / timedOut / cancelled / error). Reset at
    // the start of every `enhance(...)`.
    private var currentPrepSeconds: TimeInterval?
    private var currentTtftSeconds: TimeInterval?
    private var currentGenSeconds: TimeInterval?
    private var currentOutputChars: Int = 0
    /// Set by the wall-clock timeout task before it throws, so the outer
    /// catch can disambiguate `.timedOut` from a generic `.error`.
    private var lastTimeoutFired: Bool = false

    /// W11.A3 — effective promptMode for the current `enhance(...)` call.
    /// Defaults to whatever the caller passed in (`.standard` / `.fastPath`)
    /// and is upgraded to `.kvCacheReuse` from inside the cache-hit branch
    /// of `runEnhance`. Read by `recordOutcome` when emitting the CSV row.
    private var currentPromptMode: EnhancementTimingLogger.PromptMode = .standard

    #if canImport(MLXLLM)
    /// W11.A3 — cached system-prefix KV cache. Populated on the first
    /// enhance() with a given (modelId, system-prompt-hash, common-prefix-
    /// token-count); reused (via `.copy()`) on subsequent calls that share the
    /// same triple. Invalidated on model swap, `reset()`, or idle eviction.
    /// `@unchecked Sendable` because the underlying KVCache instances hold
    /// MLXArray state which is not formally Sendable; safety relies on actor
    /// isolation + always copying before crossing into ModelContainer's actor.
    private struct CachedSystemPrefill: @unchecked Sendable {
        let modelId: String
        let systemHash: String
        let cache: [any KVCache]
        let systemTokenCount: Int
    }
    private var cachedPrefill: CachedSystemPrefill?

    /// Sendable carrier so we can ferry CachedSystemPrefill across the
    /// `container.perform` Sendable closure boundary in either direction.
    private struct PrefillBox: @unchecked Sendable {
        let value: CachedSystemPrefill
    }
    #endif

    private func markTimeoutFired() {
        self.lastTimeoutFired = true
    }

    private func setCurrentPromptMode(_ mode: EnhancementTimingLogger.PromptMode) {
        self.currentPromptMode = mode
    }

    #if canImport(MLXLLM)
    private func storeCachedPrefill(_ box: PrefillBox) {
        self.cachedPrefill = box.value
    }

    private func loadCachedPrefill() -> PrefillBox? {
        cachedPrefill.map { PrefillBox(value: $0) }
    }

    private func invalidateCachedPrefill() {
        if cachedPrefill != nil {
            Self.logger.notice("🦾 kv-cache-reuse: invalidated cached system prefill")
        }
        cachedPrefill = nil
    }
    #endif

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
        promptMode: EnhancementTimingLogger.PromptMode = .standard
    ) async throws -> String {
        #if canImport(MLXLLM)
        // W11.A5: wall-clock timeout reuses the existing user-set
        // `EnhancementTimeoutSeconds` (default 7s). Caps cold + warm + rambling
        // outputs the same way remote-API providers are already capped at
        // AIEnhancementService.swift:74. UserDefaults read is thread-safe inside
        // an actor. Plan §Migration policy #7-#8.
        let storedTimeout = UserDefaults.standard.integer(forKey: "EnhancementTimeoutSeconds")
        let effectiveTimeout: TimeInterval = storedTimeout > 0 ? TimeInterval(storedTimeout) : 15

        // W11.D — reset per-call timing capture before kicking off the race.
        let startedAt = Date()
        self.currentPrepSeconds = nil
        self.currentTtftSeconds = nil
        self.currentGenSeconds = nil
        self.currentOutputChars = 0
        self.lastTimeoutFired = false
        // W11.A3 — start with caller's promptMode; runEnhance may upgrade
        // to .kvCacheReuse after a cache-hit fires.
        self.currentPromptMode = promptMode

        let modelIdSnapshot = self.modelId
        let inputChars = userPrompt.count

        func recordOutcome(_ outcome: EnhancementTimingLogger.Outcome) async {
            let total = Date().timeIntervalSince(startedAt)
            await EnhancementTimingLogger.shared.record(
                modelId: modelIdSnapshot,
                promptMode: self.currentPromptMode,
                inputChars: inputChars,
                outputChars: self.currentOutputChars,
                prepSeconds: self.currentPrepSeconds,
                ttftSeconds: self.currentTtftSeconds,
                genSeconds: self.currentGenSeconds,
                totalSeconds: total,
                startedAt: startedAt,
                outcome: outcome
            )
        }

        do {
            let result = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { [systemPrompt, userPrompt] in
                    try await self.runEnhance(systemPrompt: systemPrompt, userPrompt: userPrompt)
                }
                group.addTask { [effectiveTimeout] in
                    try await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                    Self.logger.warning("🦾 enhance: timeout fired after \(effectiveTimeout, format: .fixed(precision: 1), privacy: .public)s (EnhancementTimeoutSeconds)")
                    await self.markTimeoutFired()
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
            await recordOutcome(.success)
            return result
        } catch is CancellationError {
            await recordOutcome(self.lastTimeoutFired ? .timedOut : .cancelled)
            throw CancellationError()
        } catch {
            await recordOutcome(self.lastTimeoutFired ? .timedOut : .error)
            throw error
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

        // W11.A3 — opt-in system-prefix KV-cache reuse. Flag default is `false`
        // so behaviour is unchanged for existing users. Token-diff approach:
        // tokenize [.system] alone and [.system, .user] together, take the
        // common prefix, prefill that into a fresh cache, snapshot via
        // `KVCache.copy()`, then continue generation with only the user-suffix
        // tokens. Works for chatml-style templates where the system block is a
        // strict prefix of the full conversation tokenization; gracefully
        // degrades (n=0 → no benefit, no harm) for templates that interleave.
        let kvReuseEnabled = UserDefaults.standard.bool(forKey: "MLXKVCacheReuseEnabled")

        // W11.A4: temperature=0.0 routes to ArgMaxSampler; topP omitted (ignored
        // at temp=0). Quality-neutral on cleanup task; cuts 5-15ms per 100 tokens
        // and is forward-compatible with W11.C speculative decoding.
        let parameters = GenerateParameters(
            maxTokens: dynamicMaxTokens,
            temperature: 0.0
        )

        do {
            try Task.checkCancellation()

            let output: String
            if kvReuseEnabled {
                output = try await runKVReuseGeneration(
                    container: container,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    parameters: parameters,
                    dynamicMaxTokens: dynamicMaxTokens
                )
            } else {
                output = try await runStandardGeneration(
                    container: container,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    parameters: parameters,
                    dynamicMaxTokens: dynamicMaxTokens
                )
            }

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

    /// Existing W11.A path (unchanged behaviour) — single full chat-template
    /// prefill, then stream. Used when `MLXKVCacheReuseEnabled=false` (default).
    private func runStandardGeneration(
        container: ModelContainer,
        systemPrompt: String,
        userPrompt: String,
        parameters: GenerateParameters,
        dynamicMaxTokens: Int
    ) async throws -> String {
        let prepStart = Date()
        let messages: [Chat.Message] = [
            .system(systemPrompt),
            .user(userPrompt),
        ]
        let userInput = UserInput(chat: messages)
        let input = try await container.prepare(input: userInput)
        let prepElapsed = Date().timeIntervalSince(prepStart)
        self.currentPrepSeconds = prepElapsed

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
        self.currentTtftSeconds = ttft
        self.currentGenSeconds = genElapsed
        self.currentOutputChars = output.count
        Self.logger.notice("🦾 enhance: gen=\(genElapsed, format: .fixed(precision: 2), privacy: .public)s ttft=\(ttft, format: .fixed(precision: 2), privacy: .public)s tokens≈\(chunkCount, privacy: .public) (\(tokenRate, format: .fixed(precision: 1), privacy: .public) tok/s) output=\(output.count, privacy: .public)c")

        return output
    }

    /// W11.A3 — system-prefix KV-cache reuse path. Falls back to a standard
    /// full-prefill in the same call when the common-prefix length is zero
    /// (template has no shared prefix between system-only and full chat).
    /// On cache hit, restores a `.copy()` of the snapshot and feeds only the
    /// user-suffix tokens; on miss, runs system-only prefill, snapshots, then
    /// continues with the user-suffix on the same cache.
    private func runKVReuseGeneration(
        container: ModelContainer,
        systemPrompt: String,
        userPrompt: String,
        parameters: GenerateParameters,
        dynamicMaxTokens: Int
    ) async throws -> String {
        let prepStart = Date()

        // Tokenize twice via the container so the chat template is applied
        // consistently with the rest of the codebase. Both calls return
        // `LMInput` via `sending`, so we can read `.text.tokens` here.
        let sysOnlyInput = UserInput(chat: [.system(systemPrompt)])
        let fullInput = UserInput(chat: [.system(systemPrompt), .user(userPrompt)])

        let sysIds: [Int]
        let fullIds: [Int]
        do {
            let lmSysOnly = try await container.prepare(input: sysOnlyInput)
            let lmFull = try await container.prepare(input: fullInput)
            sysIds = lmSysOnly.text.tokens.asArray(Int.self)
            fullIds = lmFull.text.tokens.asArray(Int.self)
        } catch {
            // Some chat templates require user/assistant alternation and
            // refuse system-only. Fall back to the standard path so we still
            // produce output rather than failing the enhancement.
            Self.logger.warning("🦾 kv-cache-reuse: tokenization failed (\(error.localizedDescription, privacy: .public)) — falling back to standard prefill")
            return try await runStandardGeneration(
                container: container,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                parameters: parameters,
                dynamicMaxTokens: dynamicMaxTokens
            )
        }

        // Walk both arrays for the longest common prefix. For chatml-style
        // templates this equals the system block (`<|im_start|>system\n…<|im_end|>\n`).
        // For legacy `[INST] <<SYS>>…` templates the prefix collapses near
        // zero — we simply skip the optimization in that case.
        var n = 0
        let upper = min(sysIds.count, fullIds.count)
        while n < upper && sysIds[n] == fullIds[n] { n += 1 }

        // Need a meaningful prefix to amortize. Below this threshold the
        // bookkeeping cost outweighs the saved prefill (RoPE pos = 0..N).
        let kMinPrefixTokens = 32
        guard n >= kMinPrefixTokens else {
            Self.logger.notice("🦾 kv-cache-reuse: skip — common-prefix=\(n, privacy: .public) tokens (<\(kMinPrefixTokens, privacy: .public))")
            return try await runStandardGeneration(
                container: container,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                parameters: parameters,
                dynamicMaxTokens: dynamicMaxTokens
            )
        }

        let systemHash = MLXProvider.sha256(systemPrompt)
        let modelIdSnap = self.modelId
        let priorBox = self.loadCachedPrefill()
        let isHit: Bool
        if let prior = priorBox?.value,
           prior.modelId == modelIdSnap,
           prior.systemHash == systemHash,
           prior.systemTokenCount == n {
            isHit = true
        } else {
            isHit = false
        }

        // Send all primitive payloads into the perform-closure; KVCache
        // instances ride via @unchecked-Sendable PrefillBox. Capturing
        // `[self]` lets us call back into the actor for storage/timing.
        let captureFullIds = fullIds
        let capturePrefixLen = n
        let captureIsHit = isHit
        let capturePrefillStep = parameters.prefillStepSize
        let captureSysHash = systemHash
        let capturePriorBox = priorBox

        struct GenerationResult: @unchecked Sendable {
            let output: String
            let firstChunkAt: TimeInterval?
            let chunkCount: Int
            let genStart: Date
            let genElapsed: TimeInterval
            let snapshotToStore: PrefillBox?
            let didHit: Bool
            let prefilledSystemTokens: Int
        }

        let result: GenerationResult = try await container.perform { ctx in
            var streamCache: [any KVCache]? = nil
            var streamInput: LMInput
            var snapshotForStorage: PrefillBox? = nil
            var didHit = false

            if captureIsHit, let prior = capturePriorBox?.value {
                // CACHE HIT — copy the snapshot so the stored one stays at
                // offset = systemTokenCount across calls.
                let cacheCopy = prior.cache.map { $0.copy() }
                let userSuffix = MLXArray(Array(captureFullIds[capturePrefixLen...]))
                streamInput = LMInput(tokens: userSuffix)
                streamCache = cacheCopy
                didHit = true
            } else {
                // MISS — build a fresh cache, prefill the system prefix,
                // snapshot it, then continue with the user suffix on the
                // same cache (which is already at offset = N).
                let freshCache = MLXLMCommon.makePromptCache(
                    model: ctx.model, parameters: parameters)
                let prefixTokens = MLXArray(Array(captureFullIds[..<capturePrefixLen]))
                var y = LMInput.Text(tokens: prefixTokens)
                while y.tokens.size > capturePrefillStep {
                    let chunk = y[.newAxis, ..<capturePrefillStep]
                    _ = ctx.model(chunk, cache: freshCache, state: nil)
                    eval(freshCache as [Any])
                    y = y[capturePrefillStep...]
                }
                if y.tokens.size > 0 {
                    let chunk = y[.newAxis, 0...]
                    _ = ctx.model(chunk, cache: freshCache, state: nil)
                    eval(freshCache as [Any])
                }
                let snap = freshCache.map { $0.copy() }
                let newPrefill = CachedSystemPrefill(
                    modelId: modelIdSnap,
                    systemHash: captureSysHash,
                    cache: snap,
                    systemTokenCount: capturePrefixLen
                )
                snapshotForStorage = PrefillBox(value: newPrefill)

                let userSuffix = MLXArray(Array(captureFullIds[capturePrefixLen...]))
                streamInput = LMInput(tokens: userSuffix)
                streamCache = freshCache
            }

            let stream = try MLXLMCommon.generate(
                input: streamInput,
                cache: streamCache,
                parameters: parameters,
                context: ctx
            )

            var output = ""
            var firstChunkAt: TimeInterval?
            var chunkCount = 0
            let genStart = Date()
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

            return GenerationResult(
                output: output,
                firstChunkAt: firstChunkAt,
                chunkCount: chunkCount,
                genStart: genStart,
                genElapsed: genElapsed,
                snapshotToStore: snapshotForStorage,
                didHit: didHit,
                prefilledSystemTokens: capturePrefixLen
            )
        }

        // Stash the new snapshot (miss path) so subsequent calls can hit.
        if let newSnap = result.snapshotToStore {
            self.storeCachedPrefill(newSnap)
            Self.logger.notice("🦾 kv-cache-reuse: stored snapshot modelId=\(modelIdSnap, privacy: .public) systemTokenCount=\(result.prefilledSystemTokens, privacy: .public)")
        }
        if result.didHit {
            self.currentPromptMode = .kvCacheReuse
            Self.logger.notice("🦾 kv-cache-reuse: hit modelId=\(modelIdSnap, privacy: .public) systemTokenCount=\(result.prefilledSystemTokens, privacy: .public)")
        }

        // Prep elapsed covers the double-tokenization + (on miss) the
        // synchronous system-prefill. ttft is wall-clock from `genStart`
        // inside perform; on a hit, that includes only the user-suffix
        // prefill which is the whole point of the optimization.
        let prepElapsed = Date().timeIntervalSince(prepStart) - result.genElapsed
        let ttft = result.firstChunkAt ?? result.genElapsed
        let tokenRate = result.genElapsed > 0 ? Double(result.chunkCount) / result.genElapsed : 0
        self.currentPrepSeconds = max(0, prepElapsed)
        self.currentTtftSeconds = ttft
        self.currentGenSeconds = result.genElapsed
        self.currentOutputChars = result.output.count

        Self.logger.notice("🦾 enhance: prep=\(prepElapsed, format: .fixed(precision: 2), privacy: .public)s maxTokens=\(dynamicMaxTokens, privacy: .public) input=\(userPrompt.count, privacy: .public)c hit=\(result.didHit, privacy: .public)")
        Self.logger.notice("🦾 enhance: gen=\(result.genElapsed, format: .fixed(precision: 2), privacy: .public)s ttft=\(ttft, format: .fixed(precision: 2), privacy: .public)s tokens≈\(result.chunkCount, privacy: .public) (\(tokenRate, format: .fixed(precision: 1), privacy: .public) tok/s) output=\(result.output.count, privacy: .public)c")

        return result.output
    }

    /// SHA-256 hex digest of a String. Used as the cache key for the system
    /// prompt — collision-resistance isn't safety-critical here, but a strong
    /// hash avoids accidental hash collisions when system prompts differ by a
    /// single character.
    nonisolated static func sha256(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    #endif

    /// Drop the loaded model and cancel pending eviction. Called when the user
    /// switches to a different MLX model or away from MLX entirely.
    func reset() {
        evictTask?.cancel()
        evictTask = nil
        #if canImport(MLXLLM)
        modelContainer = nil
        // W11.A3 — KV-cache snapshot is bound to a specific model's weights;
        // invalidate when the model is dropped to avoid feeding incompatible
        // cache state into a freshly loaded (potentially different) model.
        invalidateCachedPrefill()
        #endif
        lastUsedAt = nil
    }

    /// W11.A1: load weights into memory without running enhance. Idempotent —
    /// a second call when warm is a cheap actor-state check on the cached
    /// `modelContainer`. Used by the prewarm hook + recording-start fire-and-
    /// forget warm path so first-enhance-after-idle skips cold-load.
    ///
    /// W11.D: `source` is one of `appLaunch` / `wake` / `recordingStart`. Logged
    /// alongside `status=alreadyLoaded|loaded` for empirical prewarm coverage
    /// measurement.
    func warm(source: String) async throws {
        #if canImport(MLXLLM)
        guard !modelId.isEmpty else { throw ProviderError.noModelSelected }
        let alreadyLoaded = (modelContainer != nil)
        _ = try await loadModel()
        self.lastUsedAt = Date()
        self.scheduleEvictionCheck()
        let status = alreadyLoaded ? "alreadyLoaded" : "loaded"
        Self.logger.notice("🦾 prewarm: fired model=\(self.modelId, privacy: .public) source=\(source, privacy: .public) status=\(status, privacy: .public)")
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
        // W11.A3 — drop the cache snapshot too; it's only valid against the
        // weights we just unloaded and would be the wrong size on next load.
        invalidateCachedPrefill()
        Self.logger.notice("🦾 evicted \(self.modelId, privacy: .public) after idle (idleEvictSeconds=\(Int(self.idleEvictSeconds), privacy: .public))")
        #endif
    }
}
