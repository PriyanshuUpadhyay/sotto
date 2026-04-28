import Foundation
import Combine

// MARK: - FailureRegistry
//
// Session-scoped store for unresolved failures. Subscribes to an external
// publisher of `FailureEvent`s (typically `VoiceInkEngine.failurePublisher`),
// surfaces the latest unacked event via `current`, and exposes
// `unresolvedCount` as a separate signal so the menubar dot can persist past
// the cluster's dwell.
//
// Lifetime contract:
//   • Session-scoped only. No UserDefaults / SwiftData persistence. Failures
//     vanish on app relaunch — by design.
//
// Sentinel:
//   • The companion `@AppStorage("failedDwellSeconds")` knob accepts:
//       3.0  → cluster auto-dismisses after 3 seconds
//       6.0  → cluster auto-dismisses after 6 seconds
//       Double.infinity → cluster persists until RETRY / OPEN SETTINGS / ack
//     The registry itself never reads this value — the cluster reads it and
//     decides when to call `acknowledge(id:)`. Documented here so a coder
//     reading the registry knows where the timing decision lives.
//
// Auto-ack hooks (wired in `init`):
//   • `.navigateToDestination` notification with userInfo["destination"]
//     starting with "Settings" → calls `clearAll()`. Catches the cluster's
//     OPEN SETTINGS chip, the menubar Settings menu, hotkey paths, and any
//     other Settings deep-link.

@MainActor
final class FailureRegistry: ObservableObject {
    @Published private(set) var current: FailureEvent?
    @Published private(set) var unresolvedCount: Int = 0

    private var cancellables = Set<AnyCancellable>()
    private var settingsAckObserver: NSObjectProtocol?

    init() {
        installSettingsAckObserver()
    }

    deinit {
        if let observer = settingsAckObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Publishing

    /// External callers push a failure with just a reason string; the
    /// registry mints the id + timestamp.
    func publish(reason: String) {
        let event = FailureEvent(reason: reason)
        current = event
        unresolvedCount += 1
    }

    /// Ack a single event by id. Clears `current` only if the latest event
    /// matches the id; decrements `unresolvedCount` regardless (clamped at
    /// 0). Cluster + menubar both pass an id they observed via `current`,
    /// so the count semantics ("user saw an event") hold even when a fresh
    /// publish has bumped `current` past the acked one.
    func acknowledge(_ id: UUID) {
        if current?.id == id {
            current = nil
        }
        if unresolvedCount > 0 {
            unresolvedCount -= 1
        }
    }

    /// Drop everything. Used by the success path (engine clears after a
    /// clean `runPipeline`) and by the Settings-open auto-ack hook.
    func clearAll() {
        current = nil
        unresolvedCount = 0
    }

    // MARK: - Engine attachment

    /// Subscribe to a `VoiceInkEngine`-shaped failure publisher. Kept as an
    /// external attach call rather than an injected reference so the engine
    /// stays unaware of `FailureRegistry`'s existence.
    func attach<P: Publisher>(to publisher: P)
    where P.Output == FailureEvent, P.Failure == Never {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                self.current = event
                self.unresolvedCount += 1
            }
            .store(in: &cancellables)
    }

    // MARK: - Settings-open auto-ack

    private func installSettingsAckObserver() {
        settingsAckObserver = NotificationCenter.default.addObserver(
            forName: .navigateToDestination,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let dest = note.userInfo?["destination"] as? String,
                  dest.hasPrefix("Settings") else { return }
            Task { @MainActor in
                self?.clearAll()
            }
        }
    }
}
