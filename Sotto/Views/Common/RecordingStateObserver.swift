import Combine
import SwiftUI

// MARK: - RecordingStateObserver
//
// Combine bridge: `engine.$recordingState` → `IconState`, deduped on the main
// queue. Owned by `AppDelegate` so its lifetime tracks the app process; the
// stored cancellable is released in `deinit`.
//
// `bind(to:)` is `@MainActor` because `SottoEngine` is main-actor-isolated
// and reading `engine.$recordingState` requires that context. The class itself
// stays nonisolated so `AppDelegate` can stash an instance as a stored property.

final class RecordingStateObserver: ObservableObject {
    @Published private(set) var iconState: MenuBarIconRenderer.IconState = .idle
    @Published private(set) var unresolvedFailures: Int = 0

    private var stateCancellable: AnyCancellable?
    private var registryCancellable: AnyCancellable?

    // View-side phase published by HUD pair. Defaults to `.hidden` so engine
    // state drives behavior until HUD wires its publisher via `bind(toHalo:)`.
    private let haloPhaseSubject = CurrentValueSubject<HaloPhase, Never>(.hidden)
    private var haloCancellable: AnyCancellable?

    @MainActor
    func bind(to engine: SottoEngine) {
        stateCancellable?.cancel()
        // CombineLatest: engine recording state + view-side HaloPhase.
        // Precedence inside IconState's combined init: halo view-state > engine
        // state. Until HUD invokes `bind(toHalo:)`, haloPhaseSubject stays
        // `.hidden` and engine state alone drives the icon — backward-compatible.
        stateCancellable = Publishers.CombineLatest(
            engine.$recordingState,
            haloPhaseSubject
        )
        .receive(on: DispatchQueue.main)
        .map { recordingState, haloPhase in
            MenuBarIconRenderer.IconState(
                recordingState: recordingState,
                haloPhase: haloPhase
            )
        }
        .removeDuplicates()
        .sink { [weak self] next in
            self?.iconState = next
        }
    }

    @MainActor
    func bind(toRegistry registry: FailureRegistry) {
        registryCancellable?.cancel()
        registryCancellable = registry.$unresolvedCount
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] next in
                self?.unresolvedFailures = next
            }
    }

    /// HUD pair calls this with a publisher of `HaloPhase` so the menubar
    /// reflects view-lifetime states (`.armed`, `.done`, `.failed`) that engine
    /// state alone doesn't expose. Until called, haloPhaseSubject stays
    /// `.hidden` — backward-compatible.
    @MainActor
    func bind<P: Publisher>(toHalo publisher: P) where P.Output == HaloPhase, P.Failure == Never {
        haloCancellable?.cancel()
        haloCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.haloPhaseSubject.send(phase)
            }
    }

    deinit {
        stateCancellable?.cancel()
        registryCancellable?.cancel()
        haloCancellable?.cancel()
    }
}
