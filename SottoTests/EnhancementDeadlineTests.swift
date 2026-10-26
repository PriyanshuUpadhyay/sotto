import Testing
import Foundation
@testable import Sotto

struct EnhancementDeadlineTests {

    private actor Flag {
        private(set) var value = false
        func set() { value = true }
    }

    private actor Tally {
        private(set) var durations: [Duration] = []
        func record(_ duration: Duration) { durations.append(duration) }
    }

    /// One-shot gate the test opens itself — replaces a sleep as the way to
    /// order two tasks. Deliberately not cancellation-aware.
    private actor Latch {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func open() {
            isOpen = true
            let pending = waiters
            waiters = []
            for continuation in pending { continuation.resume() }
        }

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    /// The deadline timer is injected, so none of these tests measure wall-clock
    /// time: a timer that never fires is `Task.sleep` for an hour (it only ends
    /// when the group cancels it), and a timer that fires at once is `{ _ in }`.
    /// A regression that would only show as a hang carries a `.timeLimit` so it
    /// fails instead of stalling the run.
    @Test(.timeLimit(.minutes(1)))
    func operationFasterThanDeadlineReturnsPromptly() async throws {
        let timerCancelled = Flag()
        let result = try await withEnhancementDeadline(seconds: 2.0, sleep: { _ in
            do {
                try await Task.sleep(for: .seconds(3600)) // never fires
            } catch {
                await timerCancelled.set()
                throw error
            }
        }) {
            "ok"
        }
        #expect(result == "ok")
        // Regression guard: a task group returning normally does NOT auto-cancel
        // its still-running timeout sibling, so a fast result must cancel the
        // timer itself. Without that, the group waits on the timer that never
        // fires (here: a hang, caught by the time limit) instead of returning.
        #expect(await timerCancelled.value, "the losing timeout timer should have been cancelled")
    }

    @Test(.timeLimit(.minutes(1)))
    func slowOperationTimesOutAndIsCancelled() async {
        let cancelled = Flag()
        do {
            _ = try await withEnhancementDeadline(seconds: 0.2, sleep: { _ in }) { () -> String in // timer fires at once
                do {
                    try await Task.sleep(for: .seconds(3600)) // never finishes on its own
                    return "unreachable"
                } catch is CancellationError {
                    await cancelled.set()
                    throw CancellationError()
                }
            }
            Issue.record("expected withEnhancementDeadline to throw .timeout")
        } catch let error as EnhancementError {
            guard case .timeout = error else {
                Issue.record("expected .timeout, got \(error)")
                return
            }
        } catch {
            Issue.record("expected EnhancementError.timeout, got \(error)")
        }
        // Structured-concurrency teardown awaits the cancelled child task
        // before withEnhancementDeadline returns, so this is already set. A
        // timeout that abandoned the operation instead of cancelling it would
        // leave it running (or hang the group, caught by the time limit).
        #expect(await cancelled.value)
    }

    /// ONE total deadline across ALL attempts inside `operation` — a timeout
    /// must still fire while a LATER step is running, after an earlier step
    /// already finished. The injected timer only fires once the second step
    /// has started, and is asked for the full deadline exactly once: a
    /// regression to separate per-attempt deadlines would arm a timer per
    /// step (or stop the first one), so either the second step would never be
    /// cut off or `durations` would not be a single full-length entry.
    @Test(.timeLimit(.minutes(1)))
    func deadlineCoversAllStepsInsideOperationWithoutCompounding() async {
        let secondStepStarted = Latch()
        let timers = Tally()
        do {
            _ = try await withEnhancementDeadline(seconds: 1.0, sleep: { duration in
                await timers.record(duration)
                await secondStepStarted.wait()
            }) { () -> String in
                await Task.yield() // first step: finishes on its own, well inside the deadline
                await secondStepStarted.open()
                try await Task.sleep(for: .seconds(3600)) // second step: only the deadline can end it
                return "unreachable"
            }
            Issue.record("expected withEnhancementDeadline to throw .timeout")
        } catch let error as EnhancementError {
            guard case .timeout = error else {
                Issue.record("expected .timeout, got \(error)")
                return
            }
        } catch {
            Issue.record("expected EnhancementError.timeout, got \(error)")
        }
        #expect(await timers.durations == [.seconds(1.0)], "expected one timer for the whole operation")
    }
}
