import Foundation

// MARK: - FailureEvent
//
// Single failure occurrence emitted by `VoiceInkEngine.failurePublisher` and
// stored by `FailureRegistry`. Identity is the UUID — two publishes with the
// same reason string still produce distinct events, so a repeat failure
// re-mounts the cluster and increments `unresolvedCount`.

struct FailureEvent: Identifiable, Equatable {
    let id: UUID
    let reason: String
    let timestamp: Date

    init(reason: String, id: UUID = UUID(), timestamp: Date = Date()) {
        self.id = id
        self.reason = reason
        self.timestamp = timestamp
    }

    static func == (lhs: FailureEvent, rhs: FailureEvent) -> Bool {
        lhs.id == rhs.id
    }
}
