import FluidAudio
import Foundation
import os

/// Generic single-resident-key coordinator with session-OWNERSHIP (lease)
/// semantics, not just value caching: `acquire` returns a lease the caller
/// MUST release when done, and `onReuse` (reset) only ever runs on a value
/// that isn't currently leased — a same-key acquire while leased waits for
/// the release (single-waiter: only one dictation is ever active in
/// practice, but a second concurrent wait is still safe). A different-key
/// acquire competes via a generation counter bumped synchronously — no
/// `await` between "bump generation", "evict the loser", and "register this
/// key's load" — so concurrent different-key acquires always agree on
/// exactly one eventual winner, even if the loser's load finishes first.
///
/// Generic over `Key` (not `Value`) because ONE instance coordinates
/// residency across heterogeneous value types (the three distinct FluidAudio
/// streaming manager actors) — the loaded value and its cleanup closure are
/// stored type-erased (`Any`) and cast back using each call's own `Value`
/// type parameter.
actor FamilyResidencyCoordinator<Key: Hashable> {
    private var generation = 0
    private var claimedKey: Key?
    private var value: Any?
    private var valueCleanup: ((Any) async -> Void)?
    private var loadingTask: Task<Any, Error>?
    private var lease: UUID?
    private var releaseWaiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    // Set by evictAll(force: false) when a lease is currently outstanding:
    // defers the actual teardown until the lease-holder calls release(),
    // instead of destroying a manager a live session is still using.
    private var pendingEvict = false

    /// Acquires `key`'s value, waiting out any outstanding lease first
    /// (regardless of which key holds it — only one key is ever resident).
    /// Throws `CancellationError` if the caller is cancelled while waiting.
    func acquire<Value>(
        key: Key,
        onReuse: (Value) async throws -> Void,
        load: @escaping @Sendable () async throws -> Value,
        cleanup cleanupValue: @escaping (Value) async -> Void
    ) async throws -> (Value, UUID) {
        guard let result = try await acquireCore(key: key, onReuse: onReuse, load: load, cleanup: cleanupValue, waitIfLeased: true) else {
            preconditionFailure("acquireCore must produce a result when waitIfLeased is true")
        }
        return result
    }

    /// Best-effort warm-up: never waits, never resets/evicts a leased value.
    /// A no-op if a lease is outstanding for any key when this is called.
    func prewarm<Value>(
        key: Key,
        onReuse: (Value) async throws -> Void,
        load: @escaping @Sendable () async throws -> Value,
        cleanup cleanupValue: @escaping (Value) async -> Void
    ) async throws {
        guard let (_, leaseId) = try await acquireCore(key: key, onReuse: onReuse, load: load, cleanup: cleanupValue, waitIfLeased: false) else {
            return
        }
        await release(key: key, leaseId: leaseId)
    }

    /// Releases a lease acquired via `acquire`/`prewarm`. Safe to call more
    /// than once, or with a stale/mismatched id — a no-op unless it exactly
    /// matches the current lease. Performs a deferred `evictAll()` if one was
    /// requested while this lease was outstanding.
    func release(key: Key, leaseId: UUID) async {
        guard claimedKey == key, lease == leaseId else { return }
        lease = nil
        if pendingEvict {
            await performEvict()
            return
        }
        guard !releaseWaiters.isEmpty else { return }
        releaseWaiters.removeFirst().continuation.resume()
    }

    /// Whether `key`'s value is currently loaded (leased or not).
    func isResident(key: Key) -> Bool {
        claimedKey == key && value != nil
    }

    /// Teardown for a deliberate model switch or app-launch reset. If a
    /// lease is outstanding and `force` is false (the default), defers the
    /// actual teardown until `release` is called for that lease — never
    /// destroys a manager a live session is still using. `force: true` tears
    /// down immediately regardless (no current caller needs this, but the
    /// option is kept for a future one that can prove no session is active).
    func evictAll(force: Bool = false) async {
        guard force || lease == nil else {
            pendingEvict = true
            return
        }
        await performEvict()
    }

    private func performEvict() async {
        generation += 1
        claimedKey = nil
        let previousValue = value
        let previousCleanup = valueCleanup
        value = nil
        valueCleanup = nil
        lease = nil
        pendingEvict = false
        let waiters = releaseWaiters
        releaseWaiters = []
        waiters.forEach { $0.continuation.resume() }
        if let previousValue, let previousCleanup {
            await previousCleanup(previousValue)
        }
    }

    /// Suspends until this slot's lease is released, or throws
    /// `CancellationError` promptly if the caller is cancelled first —
    /// waiting on a lease must never hang a cancelled caller forever.
    private func waitForRelease() async throws {
        let waiterId = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                releaseWaiters.append((waiterId, continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: waiterId) }
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = releaseWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = releaseWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func acquireCore<Value>(
        key: Key,
        onReuse: (Value) async throws -> Void,
        load: @escaping @Sendable () async throws -> Value,
        cleanup cleanupValue: @escaping (Value) async -> Void,
        waitIfLeased: Bool
    ) async throws -> (Value, UUID)? {
        if lease != nil {
            guard waitIfLeased else { return nil }
            try await waitForRelease()
            return try await acquireCore(key: key, onReuse: onReuse, load: load, cleanup: cleanupValue, waitIfLeased: waitIfLeased)
        }

        if claimedKey == key, let value, let typed = value as? Value {
            // Claim the lease BEFORE the (suspending) reset call, so no
            // concurrent caller can observe `lease == nil` and slip in.
            let newLease = UUID()
            lease = newLease
            do {
                try await onReuse(typed)
            } catch {
                // reset() failed — evict the now-suspect cached value instead
                // of leaving it in place for the next caller to retry the
                // same failing reuse forever; the next acquire does a fresh load.
                lease = nil
                generation += 1
                claimedKey = nil
                self.value = nil
                valueCleanup = nil
                pendingEvict = false
                if !releaseWaiters.isEmpty { releaseWaiters.removeFirst().continuation.resume() }
                throw error
            }
            return (typed, newLease)
        }

        if claimedKey == key, let loadingTask {
            _ = try await loadingTask.value
            return try await acquireCore(key: key, onReuse: onReuse, load: load, cleanup: cleanupValue, waitIfLeased: waitIfLeased)
        }

        // Synchronous claim: bump the generation, evict the loser
        // (fire-and-forget — its cleanup doesn't need to block this claim),
        // and register this key's load — no `await` in this span, so a
        // same-key joiner arriving mid-claim always sees a consistent
        // (claimedKey, loadingTask) pair instead of starting a redundant
        // second load.
        let previousValue = value
        let previousCleanup = valueCleanup
        generation += 1
        let myGeneration = generation
        claimedKey = key
        value = nil
        valueCleanup = nil

        if let previousValue, let previousCleanup {
            Task { await previousCleanup(previousValue) }
        }

        let task = Task<Any, Error> { try await load() as Any }
        loadingTask = task

        let loaded: Value
        do {
            let anyLoaded = try await task.value
            guard let typed = anyLoaded as? Value else {
                preconditionFailure("FamilyResidencyCoordinator: load() produced an unexpected type for key \(key)")
            }
            loaded = typed
        } catch {
            if generation == myGeneration {
                loadingTask = nil
            }
            throw error
        }

        if generation == myGeneration {
            loadingTask = nil
        }

        guard generation == myGeneration else {
            // A newer switch claimed a different key while this load was in
            // flight — discard our result and retry from the top.
            await cleanupValue(loaded)
            return try await acquireCore(key: key, onReuse: onReuse, load: load, cleanup: cleanupValue, waitIfLeased: waitIfLeased)
        }

        claimedKey = key
        value = loaded
        valueCleanup = { anyValue in
            guard let typed = anyValue as? Value else { return }
            await cleanupValue(typed)
        }
        let newLease = UUID()
        lease = newLease
        return (loaded, newLease)
    }
}

/// Caches the three true-streaming FluidAudio managers (Unified, EOU,
/// Nemotron) across dictations so back-to-back recordings reuse a warm
/// manager instead of paying `loadModels()`'s ANE compile every time. Only
/// one family is resident at a time. Session ownership (lease) is enforced by
/// `FamilyResidencyCoordinator` — see there for the concurrency contract.
actor FluidAudioStreamingManagerCache {
    enum Family: Hashable {
        case unified, eou, nemotron
    }

    private let coordinator = FamilyResidencyCoordinator<Family>()
    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "FluidAudioStreamingManagerCache")

    /// Acquires the Unified manager, leased to the caller until `release`.
    func acquireUnified() async throws -> (manager: StreamingUnifiedAsrManager, leaseId: UUID) {
        let triple = unifiedTriple()
        let (manager, leaseId) = try await coordinator.acquire(key: .unified, onReuse: triple.onReuse, load: triple.load, cleanup: triple.cleanup)
        logger.notice("footprint after streaming-cache Unified acquire: \(FluidAudioTranscriptionService.residentFootprintMB(), privacy: .public) MB")
        return (manager, leaseId)
    }

    func acquireEou() async throws -> (manager: StreamingEouAsrManager, leaseId: UUID) {
        let triple = eouTriple()
        let (manager, leaseId) = try await coordinator.acquire(key: .eou, onReuse: triple.onReuse, load: triple.load, cleanup: triple.cleanup)
        logger.notice("footprint after streaming-cache EOU acquire: \(FluidAudioTranscriptionService.residentFootprintMB(), privacy: .public) MB")
        return (manager, leaseId)
    }

    func acquireNemotron() async throws -> (manager: StreamingNemotronAsrManager, leaseId: UUID) {
        let triple = nemotronTriple()
        let (manager, leaseId) = try await coordinator.acquire(key: .nemotron, onReuse: triple.onReuse, load: triple.load, cleanup: triple.cleanup)
        logger.notice("footprint after streaming-cache Nemotron acquire: \(FluidAudioTranscriptionService.residentFootprintMB(), privacy: .public) MB")
        return (manager, leaseId)
    }

    /// Releases a lease acquired via `acquireUnified`/`acquireEou`/`acquireNemotron`.
    func release(family: Family, leaseId: UUID) async {
        await coordinator.release(key: family, leaseId: leaseId)
    }

    /// Whether `model`'s streaming manager is already resident — the
    /// recorder's warm-vs-cold HUD label for streaming-cache-backed families.
    func isReady(for model: any TranscriptionModel) async -> Bool {
        if FluidAudioModelManager.isParakeetUnifiedModel(named: model.name) {
            return await coordinator.isResident(key: .unified)
        }
        if FluidAudioModelManager.isParakeetEouModel(named: model.name) {
            return await coordinator.isResident(key: .eou)
        }
        if FluidAudioModelManager.isNemotronStreamingModel(named: model.name) {
            return await coordinator.isResident(key: .nemotron)
        }
        return false
    }

    /// App-launch/record-start warmup: loads (but doesn't hold a lease on)
    /// the family for `model`. A no-op if a lease is already outstanding —
    /// this must never reset a manager a live session is using.
    func prewarm(for model: any TranscriptionModel) async throws {
        if FluidAudioModelManager.isParakeetUnifiedModel(named: model.name) {
            let triple = unifiedTriple()
            try await coordinator.prewarm(key: .unified, onReuse: triple.onReuse, load: triple.load, cleanup: triple.cleanup)
        } else if FluidAudioModelManager.isParakeetEouModel(named: model.name) {
            let triple = eouTriple()
            try await coordinator.prewarm(key: .eou, onReuse: triple.onReuse, load: triple.load, cleanup: triple.cleanup)
        } else if FluidAudioModelManager.isNemotronStreamingModel(named: model.name) {
            let triple = nemotronTriple()
            try await coordinator.prewarm(key: .nemotron, onReuse: triple.onReuse, load: triple.load, cleanup: triple.cleanup)
        }
    }

    /// Full teardown for a deliberate model switch or app-launch reset.
    func cleanup() async {
        await coordinator.evictAll()
    }

    // MARK: - Private

    private func unifiedTriple() -> (
        onReuse: (StreamingUnifiedAsrManager) async throws -> Void,
        load: @Sendable () async throws -> StreamingUnifiedAsrManager,
        cleanup: (StreamingUnifiedAsrManager) async -> Void
    ) {
        (
            onReuse: { try await $0.reset() },
            load: {
                let manager = StreamingUnifiedAsrManager(encoderPrecision: FluidAudioModelManager.parakeetUnifiedPrecision)
                try await manager.loadModels()
                return manager
            },
            cleanup: { await $0.cleanup() }
        )
    }

    private func eouTriple() -> (
        onReuse: (StreamingEouAsrManager) async throws -> Void,
        load: @Sendable () async throws -> StreamingEouAsrManager,
        cleanup: (StreamingEouAsrManager) async -> Void
    ) {
        (
            onReuse: { await $0.reset() },
            load: {
                let manager = StreamingEouAsrManager(chunkSize: .ms160)
                try await manager.loadModels(to: FluidAudioModelManager.parakeetEouCacheRootDirectory())
                return manager
            },
            cleanup: { await $0.cleanup() }
        )
    }

    private func nemotronTriple() -> (
        onReuse: (StreamingNemotronAsrManager) async throws -> Void,
        load: @Sendable () async throws -> StreamingNemotronAsrManager,
        cleanup: (StreamingNemotronAsrManager) async -> Void
    ) {
        (
            onReuse: { await $0.reset() },
            load: {
                let manager = StreamingNemotronAsrManager(requestedChunkSize: FluidAudioModelManager.nemotronStreamingChunkSize)
                try await manager.loadModels(to: FluidAudioModelManager.nemotronStreamingCacheRootDirectory())
                return manager
            },
            cleanup: { await $0.cleanup() }
        )
    }
}
