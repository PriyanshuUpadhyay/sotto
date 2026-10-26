import Foundation

/// Outcome of the post-enhancement repair guard for the most recent enhance.
enum EnhancementGuardOutcome: String, CaseIterable {
    case notRun                 // guard skipped (empty input)
    case none                   // first pass was clean — no repair needed
    case retryRecovered         // first pass suspect; hardened retry recovered it
    case deterministicFallback  // both passes suspect; deterministic cleanup used
}

/// Races `operation` against a `seconds` timer, throwing `.timeout` when it
/// fires. The timer is `sleep` (wall-clock by default) so tests can inject one.
func withEnhancementDeadline<T: Sendable>(
    seconds: TimeInterval,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // A task group that returns normally does NOT auto-cancel still-running
        // siblings (only exiting via throw does) — without this, a fast success
        // would still block until the losing timeout task finishes on its own,
        // i.e. the full deadline, on every call.
        defer { group.cancelAll() }
        group.addTask { try await operation() }
        group.addTask {
            try await sleep(.seconds(max(seconds, 0)))
            throw EnhancementError.timeout
        }
        guard let result = try await group.next() else {
            throw EnhancementError.timeout
        }
        return result
    }
}

enum EnhancementError: Error {
    case notConfigured
    case invalidResponse
    case enhancementFailed
    case networkError
    case serverError
    case rateLimitExceeded
    case timeout
    /// AFM's guardrail declined the prompt. Kept distinct from `.customError`
    /// so the pipeline can tell the user their transcript went out raw
    /// *because it was declined*, not because enhancement broke. Never
    /// retried — a refusal is deterministic for the same prompt.
    case safetyRefusal
    case customError(String)
}

extension EnhancementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Enhancement is unavailable. Enable Apple Intelligence in System Settings."
        case .invalidResponse:
            return "Invalid response from the on-device model."
        case .enhancementFailed:
            return "AI enhancement failed to process the text."
        case .networkError:
            return "Network connection failed. Check your internet."
        case .serverError:
            return "The on-device model encountered an error. Please try again later."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .timeout:
            return "Enhancement request timed out. Check your connection or increase the timeout duration."
        case .safetyRefusal:
            return "Apple Foundation Models declined this transcript (safety filter)."
        case .customError(let message):
            return message
        }
    }
}