import Foundation
import Testing
@testable import Sotto

private enum TestKey: Hashable {
    case a, b
}

private final class FakeManager {
    let id: Int
    private(set) var resetCount = 0
    private(set) var cleanupCount = 0

    init(id: Int) { self.id = id }

    func reset() async { resetCount += 1 }
    func cleanup() async { cleanupCount += 1 }
}

private actor Counter {
    private(set) var value = 0

    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}

/// Lets a test hold a `load` closure open until it explicitly wants the load
/// to "finish" — `open()` before any `wait()` call is safe (the flag persists).
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Races `operation` against a timeout; `nil` means the timeout won, not that
/// `operation` failed — used to observe "still blocked" without hanging the test.
private func firstToFinish<T>(_ operation: @escaping @Sendable () async throws -> T, timeoutNanoseconds: UInt64) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            try? await operation()
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

@Suite struct FamilyResidencyCoordinatorTests {

    @Test("back-to-back acquire+release reuses the cached manager without reloading")
    func backToBackAcquireReusesCachedManager() async throws {
        let coordinator = FamilyResidencyCoordinator<TestKey>()
        let counter = Counter()

        func load() async throws -> FakeManager {
            FakeManager(id: await counter.increment())
        }

        let (first, lease1) = try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })
        await coordinator.release(key: .a, leaseId: lease1)

        let (second, lease2) = try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })

        #expect((await counter.value) == 1)
        #expect(first === second)
        #expect(second.resetCount == 1)
        #expect(second.cleanupCount == 0)
        await coordinator.release(key: .a, leaseId: lease2)
    }

    @Test("release is idempotent and ignores a stale or fabricated lease id")
    func releaseIsIdempotentAndIgnoresStaleLeaseId() async throws {
        let coordinator = FamilyResidencyCoordinator<TestKey>()
        let counter = Counter()

        func load() async throws -> FakeManager {
            FakeManager(id: await counter.increment())
        }

        let (_, leaseId) = try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })

        await coordinator.release(key: .a, leaseId: leaseId)
        // A second release with the same (now-stale) id must be a safe no-op.
        await coordinator.release(key: .a, leaseId: leaseId)
        // A release with a fabricated id must also be a safe no-op.
        await coordinator.release(key: .a, leaseId: UUID())

        let (_, lease2) = try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })
        #expect((await counter.value) == 1, "the slot must still be cleanly reusable after the redundant releases")
        await coordinator.release(key: .a, leaseId: lease2)
    }

    @Test("a same-key acquire while leased waits for the release, then reuses instead of reloading")
    func sameKeyAcquireWhileLeasedWaitsForRelease() async throws {
        let coordinator = FamilyResidencyCoordinator<TestKey>()
        let counter = Counter()

        @Sendable func load() async throws -> FakeManager {
            FakeManager(id: await counter.increment())
        }

        let (first, leaseId1) = try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })

        // While the first lease is held, a second acquire for the same key
        // must not complete within a short window (it's blocked, not
        // evicting). The operation calls acquire() directly (not a wrapper
        // around a separately-spawned Task) so firstToFinish's cancelAll()
        // actually reaches the coordinator's own cancellable lease-wait.
        let earlyOutcome = await firstToFinish({
            try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })
        }, timeoutNanoseconds: 150_000_000)
        #expect(earlyOutcome == nil, "a same-key acquire must not complete while the first lease is outstanding")

        await coordinator.release(key: .a, leaseId: leaseId1)

        // A fresh acquire after the release must succeed and reuse (not reload).
        let (second, lease2) = try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })
        #expect(second === first)
        #expect((await counter.value) == 1, "reuse, not a second load")
        #expect(second.resetCount == 1)
        await coordinator.release(key: .a, leaseId: lease2)
    }

    @Test("prewarm never blocks and never resets a manager while it's leased")
    func prewarmNoOpsWhileLeased() async throws {
        let coordinator = FamilyResidencyCoordinator<TestKey>()
        let counter = Counter()

        func load() async throws -> FakeManager {
            FakeManager(id: await counter.increment())
        }

        let (manager, leaseId) = try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })
        #expect(manager.resetCount == 0)

        try await coordinator.prewarm(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })

        #expect((await counter.value) == 1, "prewarm must not start a second load while leased")
        #expect(manager.resetCount == 0, "prewarm must not reset a manager a live session holds")

        await coordinator.release(key: .a, leaseId: leaseId)
    }

    @Test("switching keys settles to exactly one resident key even when both loads race")
    func differentKeyAcquiresSettleToExactlyOneResident() async throws {
        let coordinator = FamilyResidencyCoordinator<TestKey>()
        let counterA = Counter()
        let counterB = Counter()
        let gate = Gate()

        async let aOutcome = firstToFinish({
            try await coordinator.acquire(
                key: .a,
                onReuse: { await $0.reset() },
                load: { let n = await counterA.increment(); await gate.wait(); return FakeManager(id: n) },
                cleanup: { await $0.cleanup() }
            )
        }, timeoutNanoseconds: 300_000_000)

        async let bOutcome = firstToFinish({
            try await coordinator.acquire(
                key: .b,
                onReuse: { await $0.reset() },
                load: { let n = await counterB.increment(); await gate.wait(); return FakeManager(id: n) },
                cleanup: { await $0.cleanup() }
            )
        }, timeoutNanoseconds: 300_000_000)

        // Let both calls register their claim/load before releasing the gate.
        try await Task.sleep(nanoseconds: 50_000_000)
        await gate.open()

        let (a, b) = await (aOutcome, bOutcome)

        #expect(!(a != nil && b != nil), "both keys must never be simultaneously acquired")
        #expect(a != nil || b != nil, "exactly one of the two acquires must win within the timeout")

        let aResident = await coordinator.isResident(key: .a)
        let bResident = await coordinator.isResident(key: .b)
        #expect(aResident != bResident, "exactly one key must end up resident, never both or neither")

        if let a { await coordinator.release(key: .a, leaseId: a.1) }
        if let b { await coordinator.release(key: .b, leaseId: b.1) }
    }

    @Test("cancelling a caller's task mid-load leaves the coordinator usable for the next caller")
    func cancelDuringLoadLeavesCoordinatorUsable() async throws {
        let coordinator = FamilyResidencyCoordinator<TestKey>()
        let counter = Counter()
        let gate = Gate()

        @Sendable func load() async throws -> FakeManager {
            let n = await counter.increment()
            await gate.wait()
            return FakeManager(id: n)
        }

        let cancelledTask = Task {
            try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        cancelledTask.cancel()

        await gate.open()
        // Cancelling this caller's own Task doesn't abort the shared
        // unstructured load (it's not cancellation-aware — that's the
        // coordinator's fresh-LOAD path, distinct from the lease-WAIT path,
        // which IS cancellable, see the test below). So this completes
        // normally and successfully leases the slot — release it, or the
        // acquire below would wait forever on a leaked lease.
        if let (_, leaseId) = try? await cancelledTask.value {
            await coordinator.release(key: .a, leaseId: leaseId)
        }

        // What matters: the coordinator itself must not be left stuck. A
        // fresh acquire must still succeed and be releasable.
        let (manager, leaseId) = try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })
        #expect(manager.id > 0)
        await coordinator.release(key: .a, leaseId: leaseId)
        #expect(await coordinator.isResident(key: .a))
    }

    @Test("cancelling a caller that's waiting on a lease throws promptly instead of hanging")
    func cancellingALeaseWaiterThrowsPromptly() async throws {
        let coordinator = FamilyResidencyCoordinator<TestKey>()
        let counter = Counter()

        func load() async throws -> FakeManager {
            FakeManager(id: await counter.increment())
        }

        let (_, leaseId1) = try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })

        let waiterTask = Task {
            try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })
        }

        // Give the waiter a chance to register itself as blocked on the lease.
        try await Task.sleep(nanoseconds: 50_000_000)
        waiterTask.cancel()

        do {
            _ = try await waiterTask.value
            Issue.record("expected the cancelled waiter to throw CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }

        // The coordinator itself must remain healthy afterward.
        await coordinator.release(key: .a, leaseId: leaseId1)
        let (_, leaseId2) = try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })
        await coordinator.release(key: .a, leaseId: leaseId2)
    }

    @Test("evictAll defers teardown while leased, then evicts once the lease releases")
    func evictAllDefersWhileLeasedThenEvictsOnRelease() async throws {
        let coordinator = FamilyResidencyCoordinator<TestKey>()
        let counter = Counter()

        func load() async throws -> FakeManager {
            FakeManager(id: await counter.increment())
        }

        let (manager, leaseId) = try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })

        await coordinator.evictAll()
        // Deferred: the live session's manager must not be torn down yet.
        #expect(manager.cleanupCount == 0)
        #expect(await coordinator.isResident(key: .a))

        await coordinator.release(key: .a, leaseId: leaseId)
        // The deferred eviction runs as part of this release.
        #expect(manager.cleanupCount == 1)
        #expect(!(await coordinator.isResident(key: .a)))

        // The slot is usable afterward with a clean fresh load.
        let (second, lease2) = try await coordinator.acquire(key: .a, onReuse: { await $0.reset() }, load: load, cleanup: { await $0.cleanup() })
        #expect(second !== manager)
        #expect((await counter.value) == 2)
        await coordinator.release(key: .a, leaseId: lease2)
    }
}
