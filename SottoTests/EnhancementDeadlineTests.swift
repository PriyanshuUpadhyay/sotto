import Testing
import Foundation
@testable import Sotto

struct EnhancementDeadlineTests {

    private actor Flag {
        private(set) var value = false
        func set() { value = true }
    }

    @Test func operationFasterThanDeadlineReturnsPromptly() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await withEnhancementDeadline(seconds: 2.0) {
            "ok"
        }
        let elapsed = clock.now - start
        #expect(result == "ok")
        // Regression guard: a task group returning normally does NOT auto-cancel
        // its still-running timeout sibling, so a fast result must still come
        // back promptly rather than waiting out the full 2s deadline.
        #expect(elapsed < .milliseconds(500), "expected a fast return, took \(elapsed)")
    }

    @Test func slowOperationTimesOutAndIsCancelled() async {
        let cancelled = Flag()
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await withEnhancementDeadline(seconds: 0.2) { () -> String in
                do {
                    try await Task.sleep(for: .seconds(5))
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
        let elapsed = clock.now - start
        #expect(elapsed < .seconds(2), "timeout should fire near the 0.2s deadline, not wait for the 5s operation (elapsed=\(elapsed))")
        // Structured-concurrency teardown awaits the cancelled child task
        // before withEnhancementDeadline returns, so this is already set.
        #expect(await cancelled.value)
    }

    /// ONE total deadline across ALL attempts inside `operation` — two steps
    /// that EACH individually fit under the deadline, but whose sum exceeds
    /// it, must still cut off around the deadline. Each step alone finishing
    /// under budget (unlike a single already-too-long step) is what rules out
    /// a regression to separate per-attempt deadlines.
    @Test func deadlineCoversAllStepsInsideOperationWithoutCompounding() async {
        let secondStepStarted = Flag()
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await withEnhancementDeadline(seconds: 1.0) { () -> String in
                try await Task.sleep(for: .milliseconds(600))
                await secondStepStarted.set()
                try await Task.sleep(for: .milliseconds(600))
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
        let elapsed = clock.now - start
        #expect(await secondStepStarted.value, "first 600ms step fits the 1s deadline, so the second step should have started")
        #expect(elapsed < .milliseconds(1500), "deadline should cut off around 1s total (mid second step), not ~2s for both 600ms steps to finish (elapsed=\(elapsed))")
    }
}
