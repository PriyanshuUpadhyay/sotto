import Foundation

// MARK: - ClusterPhase
//
// Cluster-side phase. Distinct from `HaloPhase` (legacy onboarding) so chip
// factories carry payloads inline. Source of truth for cluster grammar:
// docs/superpowers/specs/2026-04-28-aesthetic-redesign.md §4.

enum ClusterPhase: Equatable {
    case idle
    case recording
    case transcribing
    case enhancing
    case done(appName: String?, preview: String?)
    case failed(reason: String?)
}

extension ClusterPhase {
    /// Coarse identity — used for `.id` keys on per-chip transitions so a
    /// failed→failed transition with a different reason does not re-mount
    /// the whole row.
    var identity: String {
        switch self {
        case .idle:         return "idle"
        case .recording:    return "recording"
        case .transcribing: return "transcribing"
        case .enhancing:    return "enhancing"
        case .done:         return "done"
        case .failed:       return "failed"
        }
    }

    var isVisible: Bool {
        switch self {
        case .idle: return false
        default:    return true
        }
    }
}

// MARK: - RecordingState bridge
//
// Engine-side `RecordingState` → cluster `ClusterPhase`. `.busy` collapses
// to `.idle`. Failure does not flow through this bridge — `ClusterPhase
// .failed` is sourced from `FailureRegistry` at the orchestrator. `.done`
// is also not derived here — done synthesis lives on the orchestrator
// (PasteEvent freshness window).

extension ClusterPhase {
    /// Engine-side `RecordingState` carries no `.failed` case; failures
    /// flow as one-shot events via `FailureRegistry.$current` and feed
    /// `ClusterPhase.failed` directly on the orchestrator. This function
    /// therefore never returns `.failed`.
    static func fromEngine(_ state: RecordingState) -> ClusterPhase {
        switch state {
        case .idle, .busy:
            return .idle
        case .starting, .recording:
            return .recording
        case .transcribing:
            return .transcribing
        case .enhancing:
            return .enhancing
        }
    }
}
