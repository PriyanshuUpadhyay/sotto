import AppKit
import Combine
import SwiftUI

// MARK: - MenuBarIconRenderer
//
// Programmatic NSImage builders for the menu bar status icon. Every state
// renders the Sotto brand glyph (vertical mark + full-width underscore) at
// 18×18pt as a static, non-template NSImage — static because a SwiftUI /
// TimelineView / Canvas label re-rasterises every frame inside MenuBarExtra and
// pins the main thread (see commit history). That same constraint keeps the bar
// CALM by design: the W14 matte restyle maps each state to the shared
// `CapsuleState` and colors the underscore "signal" with `capsuleState.color`
// (phosphor idle, sacred red recording, blue processing, green commit, amber
// fail); terminal states swap the mark for the `StateCue` shape cue. No live
// animation — so Reduce Motion is satisfied vacuously (nothing to bypass), and
// the Canvas/animated migration the plan mentions stays DEFERRED behind the
// main-thread-pinning hazard. State is carried by underscore/mark color, a 4pt
// corner dot, and the terminal glyph; see `image(for:unresolvedFailures:)`.

enum MenuBarIconRenderer {
    /// Canvas size — 18×18pt, the spec-pinned non-jitter footprint.
    static let pointSize: CGFloat = 18.0

    /// Icon state — derived from engine `RecordingState` + view-side `HaloPhase`
    /// (which holds `.done` for ~1.5s post-commit and `.failed` until dismissed).
    /// Failure-registry overlay is composited as a red corner dot by
    /// `image(for:unresolvedFailures:)`.
    enum IconState: Equatable {
        case idle
        case arming         // HaloPhase.armed — pre-first-audio breathe
        case recording
        case transcribing
        case enhancing
        case committed      // HaloPhase.done — green dot post-commit
        case fail           // HaloPhase.failed — red `!` until dismissed

        /// Engine-only init — legacy callers without HaloPhase. The view-only
        /// cases (`.arming` / `.committed` / `.fail`) are unreachable from
        /// engine state alone; they require a HaloPhase signal.
        init(_ state: RecordingState) {
            switch state {
            case .recording:    self = .recording
            case .transcribing: self = .transcribing
            case .enhancing:    self = .enhancing
            default:            self = .idle
            }
        }

        /// HaloPhase-only init — view-side states. `.hidden` is the engine's
        /// `.idle` mirror; `.liveText` collapses into `.recording`.
        init(haloPhase: HaloPhase) {
            switch haloPhase {
            case .hidden:                self = .idle
            case .armed:                 self = .arming
            case .recording, .liveText:  self = .recording
            case .transcribing:          self = .transcribing
            case .enhancing:             self = .enhancing
            case .done:                  self = .committed
            case .failed:                self = .fail
            }
        }

        /// Combined init. Precedence: halo view-state > engine state. View-state
        /// cases win over engine state because engine returns to .idle
        /// immediately on commit/fail while the HUD holds the post-action phase.
        /// `.hidden` defers to engine state so the menubar keeps reflecting
        /// engine activity until the HUD takes over.
        init(recordingState: RecordingState, haloPhase: HaloPhase) {
            switch haloPhase {
            case .hidden:
                self.init(recordingState)
            default:
                self.init(haloPhase: haloPhase)
            }
        }

        /// The functional `CapsuleState` this icon renders as (W14 design). The
        /// menu bar restyle keys its accent off this shared enum so the bar and
        /// the recorder capsule speak the same 5-state syntax. `arming` reads as
        /// idle/ready; `transcribing`+`enhancing` collapse into `processing`.
        var capsuleState: CapsuleState {
            switch self {
            case .idle, .arming:            return .idleReady
            case .recording:                return .recording
            case .transcribing, .enhancing: return .processing
            case .committed:                return .commit
            case .fail:                     return .fail
            }
        }
    }

    /// VoiceOver label per state. Pure logic, exhaustive over `IconState` —
    /// adding a case is a compile error here. `MenuBarIcon` composes this with
    /// the unresolved-failure suffix at the view layer.
    static func accessibilityLabel(for state: IconState) -> String {
        switch state {
        case .idle:         return "Sotto idle"
        case .arming:       return "Sotto listening"
        case .recording:    return "Sotto recording"
        case .transcribing: return "Sotto transcribing"
        case .enhancing:    return "Sotto enhancing"
        case .committed:    return "Sotto committed"
        case .fail:         return "Sotto failed"
        }
    }

    // MARK: - Public icon

    /// The menu bar icon for `state`. The brand glyph is non-template, so macOS
    /// will not auto-tint the label-colored mark — its color is resolved here
    /// against `NSApp.effectiveAppearance` (covers light / dark / high-contrast).
    /// `unresolvedFailures > 0` stamps a red corner dot on top.
    static func image(for state: IconState, unresolvedFailures: Int) -> NSImage {
        var markColor = NSColor.labelColor
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            markColor = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }
        let base = glyphImage(for: state, markColor: markColor)
        guard unresolvedFailures > 0 else { return base }
        return stampingFailureDot(
            on: base,
            label: failedAccessibilityLabel(for: state, count: unresolvedFailures)
        )
    }

    /// Per-state brand glyph, no failure overlay. `markColor` is the already-
    /// resolved ink color for the identity mark. The "signal" — the full-width
    /// underscore — carries `capsuleState.color` (phosphor idle, sacred red
    /// recording, blue processing, green commit, amber fail), so the icon reads
    /// as the matte syntax state. Terminal states (`commit`/`fail`) swap the
    /// ink mark for the `StateCue` SF Symbol (the non-color shape cue) tinted in
    /// the state color; transient working states (`arming`/`processing`) keep the
    /// mark and add a state-colored corner dot.
    private static func glyphImage(for state: IconState, markColor: NSColor) -> NSImage {
        let label = accessibilityLabel(for: state)
        let cs = state.capsuleState
        let stateColor = NSColor(cs.color)
        switch state {
        case .idle:
            return brandGlyph(center: .mark(markColor), underscore: stateColor,
                              cornerDot: nil, label: label)
        case .arming, .transcribing, .enhancing:
            return brandGlyph(center: .mark(markColor), underscore: stateColor,
                              cornerDot: stateColor, label: label)
        case .recording:
            // Whole glyph goes sacred red — the most glanceable "live" signal.
            return brandGlyph(center: .mark(stateColor), underscore: stateColor,
                              cornerDot: nil, label: label)
        case .committed:
            return brandGlyph(center: .symbol(StateCue.glyph(for: .commit), stateColor),
                              underscore: stateColor, cornerDot: nil, label: label)
        case .fail:
            return brandGlyph(center: .symbol(StateCue.glyph(for: .fail), stateColor),
                              underscore: stateColor, cornerDot: nil, label: label)
        }
    }

    private static func failedAccessibilityLabel(for state: IconState, count: Int) -> String {
        let suffix = count == 1 ? "1 unresolved failure" : "\(count) unresolved failures"
        return "\(accessibilityLabel(for: state)), \(suffix)"
    }

    // MARK: - Brand-glyph builder

    /// What occupies the center band of the glyph.
    private enum GlyphCenter {
        case mark(NSColor)            // vertical brand bar in the given color
        case symbol(String, NSColor)  // a StateCue SF Symbol tinted, centered
    }

    /// Draws the Sotto brand glyph — vertical mark + full-width underscore — as
    /// an 18×18pt non-template NSImage. Non-template because the underscore
    /// carries a brand/state color macOS must not tint away. `underscore` is the
    /// signal color (`capsuleState.color`); `center` is the identity mark or a
    /// terminal-state `StateCue` glyph. Spec §5.2 proportions, rounded to whole
    /// points so every edge is pixel-aligned.
    private static func brandGlyph(center: GlyphCenter, underscore: NSColor,
                                   cornerDot: NSColor?, label: String) -> NSImage {
        let s = pointSize

        // Spec §5.2 proportions, rounded to whole points at the 18pt render
        // size so every edge is pixel-aligned (crisp at 1x and 2x).
        let markW = (0.18 * s).rounded()
        let markH = (0.55 * s).rounded()
        let underscoreH = (0.14 * s).rounded()
        let gap = (0.08 * s).rounded()
        let totalH = markH + gap + underscoreH
        let bottomInset = ((s - totalH) / 2.0).rounded()

        let canvas = NSImage(size: NSSize(width: s, height: s))
        canvas.lockFocus()

        // NSImage is bottom-origin: y is measured up from the bottom edge.
        // Underscore — full width, base of the stack. Carries the signal color.
        let underscoreRect = NSRect(x: 0, y: bottomInset, width: s, height: underscoreH)
        underscore.setFill()
        NSBezierPath(roundedRect: underscoreRect,
                     xRadius: underscoreH * 0.3, yRadius: underscoreH * 0.3).fill()

        // Center band — identity mark or a terminal-state StateCue glyph.
        let bandBottom = bottomInset + underscoreH + gap
        switch center {
        case .mark(let color):
            let markRect = NSRect(x: ((s - markW) / 2.0).rounded(), y: bandBottom,
                                  width: markW, height: markH)
            color.setFill()
            NSBezierPath(roundedRect: markRect,
                         xRadius: markW * 0.15, yRadius: markW * 0.15).fill()
        case .symbol(let name, let color):
            // StateCue SF Symbol sized to the mark band, centered. This is the
            // non-color shape cue (check vs. triangle) for the terminal states.
            let dim = markH + 2.0
            let cfg = NSImage.SymbolConfiguration(pointSize: dim, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            if let sym = NSImage(systemSymbolName: name, accessibilityDescription: label)?
                .withSymbolConfiguration(cfg) {
                let sz = sym.size
                sym.draw(in: NSRect(x: (s - sz.width) / 2.0,
                                    y: bandBottom + (markH - sz.height) / 2.0,
                                    width: sz.width, height: sz.height))
            }
        }

        // Corner dot — upper-right, 1pt inset.
        if let cornerDot {
            let d: CGFloat = 4.0, inset: CGFloat = 1.0
            cornerDot.setFill()
            NSBezierPath(ovalIn: NSRect(x: s - d - inset, y: s - d - inset,
                                        width: d, height: d)).fill()
        }

        canvas.unlockFocus()
        canvas.isTemplate = false
        canvas.accessibilityDescription = label
        return canvas
    }

    /// Re-renders `base` with a red corner dot stamped upper-right — the
    /// unresolved-failure overlay. Works for any 18pt icon and visually
    /// replaces any state dot already at that corner.
    private static func stampingFailureDot(on base: NSImage, label: String) -> NSImage {
        let s = pointSize
        let canvas = NSImage(size: NSSize(width: s, height: s))
        canvas.lockFocus()
        base.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
        let d: CGFloat = 4.0, inset: CGFloat = 1.0
        NSColor(Palette.stateFail).setFill()
        NSBezierPath(ovalIn: NSRect(x: s - d - inset, y: s - d - inset,
                                    width: d, height: d)).fill()
        canvas.unlockFocus()
        canvas.isTemplate = false
        canvas.accessibilityDescription = label
        return canvas
    }

}

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

struct MenuBarIcon: View {
    @ObservedObject var observer: RecordingStateObserver
    // The idle underscore carries the accent (CapsuleState.color → Palette
    // .phosphor), resolved into a static NSImage — observe the store so an
    // accent change re-renders the image.
    @ObservedObject private var accent = AccentStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Static per-state NSImage. A SwiftUI/TimelineView label re-rasterises
        // every frame inside MenuBarExtra and pins the main thread (see commit
        // history) — so the icon is a discrete image, re-rendered only when
        // iconState/unresolvedFailures/accent change. The `.id` rebuilds it
        // on a light/dark flip or accent swap; the brand glyph is non-template
        // and image(for:) re-resolves colors each rebuild.
        Image(nsImage: MenuBarIconRenderer.image(
            for: observer.iconState,
            unresolvedFailures: observer.unresolvedFailures
        ))
        .frame(width: 18, height: 18)
        .id("\(colorScheme)-\(accent.choice.rawValue)")
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        let base = MenuBarIconRenderer.accessibilityLabel(for: observer.iconState)
        guard observer.unresolvedFailures > 0 else { return base }
        let suffix = observer.unresolvedFailures == 1
            ? "1 unresolved failure"
            : "\(observer.unresolvedFailures) unresolved failures"
        return "\(base), \(suffix)"
    }
}

// MARK: - Previews

#if DEBUG
private struct MenuBarIconPreviewHarness: View {
    @State private var state: MenuBarIconRenderer.IconState = .idle
    @State private var unresolved: Int = 0

    private let allStates: [(String, MenuBarIconRenderer.IconState)] = [
        ("Idle", .idle), ("Arming", .arming), ("Recording", .recording),
        ("Transcribing", .transcribing), ("Enhancing", .enhancing),
        ("Committed", .committed), ("Fail", .fail),
    ]

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: MenuBarIconRenderer.image(
                for: state, unresolvedFailures: unresolved))
                .frame(width: 64, height: 64)

            Picker("State", selection: $state) {
                ForEach(allStates, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.menu)

            Stepper("Unresolved: \(unresolved)", value: $unresolved, in: 0...5)
        }
        .padding(32)
        .frame(width: 360)
    }
}

#Preview("Menu bar icon — Matte") {
    MenuBarIconPreviewHarness()
        .background(Palette.mtCanvas)
}

#Preview("Menu bar icon — Light") {
    MenuBarIconPreviewHarness()
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
