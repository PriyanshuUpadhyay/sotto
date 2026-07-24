import Foundation
import SwiftData

/// Exposes the separate stats.store `ModelContainer` (the one holding
/// `SessionMetric`) to call sites that can't take it via injection — the
/// transcription pipeline (writes metrics off the main actor) and the
/// History / Metrics views (read them on the main actor).
///
/// `SessionMetric` lives in its OWN container (cloudKitDatabase: .none) so
/// stats survive transcript auto-cleanup and never round-trip CloudKit. That
/// makes it unreachable from the main app container's `modelContext`, hence
/// this shared accessor.
///
/// Not `@MainActor`: it is read from BOTH the main actor (views) and the
/// background transcription actor. `ModelContainer` is `Sendable`, so handing
/// it across actors is safe. The mutable property is written exactly once at
/// launch (`SottoApp.init`) before any read, so `nonisolated(unsafe)` is
/// sound here.
final class StatsModelContainerProvider {
    static let shared = StatsModelContainerProvider()
    private init() {}

    // Set once at launch before any read; safe to access cross-actor.
    nonisolated(unsafe) var modelContainer: ModelContainer?
}
