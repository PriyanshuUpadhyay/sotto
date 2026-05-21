import AppKit
import Combine
import SwiftUI

// MARK: - MenuBarIconRenderer
//
// Programmatic NSImage builders for the four engine-driven menu bar icon
// states (idle / recording / transcribing / enhancing). Spec §3.11.
//
// All glyphs render at 18×18pt — the canvas the spec mandates so the menu bar
// row never jitters on state change. Idle / transcribing / enhancing stay
// template (auto-tinted by macOS in light + dark menu bars). Recording bakes
// `Palette.accent` directly so the loudest signal in the system reads as
// tangerine regardless of menu bar appearance.

enum MenuBarIconRenderer {
    /// Canvas size — 18×18pt, the spec-pinned non-jitter footprint.
    static let pointSize: CGFloat = 18.0

    /// SF Symbol point size — slightly inset from the canvas so glyph weight
    /// changes don't bleed past the 18pt edge into the menu bar baseline.
    static let symbolSize: CGFloat = 14.0

    /// Icon state — derived from engine `RecordingState` + view-side `HaloPhase`
    /// (which holds `.done` for ~1.5s post-commit and `.failed` until dismissed).
    /// Hands-free overrides both. Failure-registry overlay is composited at the
    /// view layer via `CornerBadge`.
    enum IconState: Equatable {
        case idle
        case arming         // HaloPhase.armed — pre-first-audio breathe
        case recording
        case transcribing
        case enhancing
        case committed      // HaloPhase.done — green dot post-commit
        case fail           // HaloPhase.failed — red `!` until dismissed
        case handsFree      // W12.D

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

        /// Combined init. Precedence: hands-free > halo view-state > engine
        /// state. View-state cases win over engine state because engine returns
        /// to .idle immediately on commit/fail while the HUD holds the
        /// post-action phase. `.hidden` defers to engine state so the menubar
        /// keeps reflecting engine activity until the HUD takes over.
        init(
            handsFree: HandsFreeSessionState,
            recordingState: RecordingState,
            haloPhase: HaloPhase
        ) {
            if handsFree != .inactive {
                self = .handsFree
                return
            }
            switch haloPhase {
            case .hidden:
                self.init(recordingState)
            default:
                self.init(haloPhase: haloPhase)
            }
        }

        /// W12.D: hands-free overrides the inner recording state. Legacy
        /// 2-arg init preserved for callers that don't yet plumb HaloPhase;
        /// delegates with `.hidden` (no view-state override).
        init(handsFree: HandsFreeSessionState, recordingState: RecordingState) {
            self.init(handsFree: handsFree, recordingState: recordingState, haloPhase: .hidden)
        }
    }

    static func image(for state: IconState) -> NSImage {
        // Legacy NSImage builders. Path A (default) renders the menubar via the
        // SwiftUI MenubarGlyphContainer in MenubarGlyph.swift; these builders
        // remain as Path B fallback and as the bridge for `.handsFree`.
        switch state {
        case .idle:
            return template("waveform", weight: .light, label: "Sotto idle")
        case .arming:
            return template("waveform", weight: .light, label: "Sotto listening")
        case .recording:
            return tinted(
                "waveform",
                weight: .semibold,
                color: NSColor(Palette.brandAcid),
                label: "Sotto recording"
            )
        case .transcribing:
            return template("waveform", weight: .regular, label: "Sotto transcribing")
        case .enhancing:
            return template("sparkles", weight: .regular, label: "Sotto enhancing")
        case .committed:
            return tinted(
                "checkmark",
                weight: .semibold,
                color: NSColor(Palette.commitGreen),
                label: "Sotto committed"
            )
        case .fail:
            return tinted(
                "exclamationmark.triangle.fill",
                weight: .semibold,
                color: NSColor(Palette.recRed),
                label: "Sotto failed"
            )
        case .handsFree:  // W12.D
            return tinted(
                "ear.fill",
                weight: .semibold,
                color: NSColor(Palette.brandAcid),
                label: "Sotto hands-free"
            )
        }
    }

    /// Failure-aware variant. When `unresolvedFailures > 0`, renders the
    /// recording-tinted waveform plus a 4pt tangerine dot in the upper-right
    /// of the 18pt canvas. Drawn by hand via `NSImage.lockFocus` — no asset
    /// dependency.
    static func image(for state: IconState, unresolvedFailures: Int) -> NSImage {
        guard unresolvedFailures > 0 else {
            return image(for: state)
        }
        return failed(label: failedAccessibilityLabel(for: state, count: unresolvedFailures))
    }

    private static func failed(label: String) -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(Palette.accent)]))
        let glyph = (NSImage(systemSymbolName: "waveform", accessibilityDescription: label)?
            .withSymbolConfiguration(cfg)) ?? NSImage()

        let canvas = NSImage(size: NSSize(width: pointSize, height: pointSize))
        canvas.lockFocus()
        defer { canvas.unlockFocus() }

        let glyphSize = glyph.size
        let originX = (pointSize - glyphSize.width) / 2.0
        let originY = (pointSize - glyphSize.height) / 2.0
        glyph.draw(in: NSRect(x: originX, y: originY, width: glyphSize.width, height: glyphSize.height))

        let dotDiameter: CGFloat = 4.0
        let dotInset: CGFloat = 1.0
        let dotRect = NSRect(
            x: pointSize - dotDiameter - dotInset,
            y: pointSize - dotDiameter - dotInset,
            width: dotDiameter,
            height: dotDiameter
        )
        NSColor(Palette.accent).setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        canvas.isTemplate = false
        canvas.accessibilityDescription = label
        return canvas
    }

    private static func failedAccessibilityLabel(for state: IconState, count: Int) -> String {
        let suffix = count == 1 ? "1 unresolved failure" : "\(count) unresolved failures"
        return "\(MenubarGlyph.accessibilityLabel(for: state)), \(suffix)"
    }

    // MARK: - Builders

    private static func template(_ symbol: String, weight: NSFont.Weight, label: String) -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: weight)
        let img = (NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(cfg)) ?? NSImage()
        img.size = NSSize(width: pointSize, height: pointSize)
        img.isTemplate = true
        return img
    }

    private static func tinted(_ symbol: String, weight: NSFont.Weight, color: NSColor, label: String) -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let glyph = (NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(cfg)) ?? NSImage()
        let canvas = NSImage(size: NSSize(width: pointSize, height: pointSize))
        canvas.lockFocus()
        let glyphSize = glyph.size
        let originX = (pointSize - glyphSize.width) / 2.0
        let originY = (pointSize - glyphSize.height) / 2.0
        glyph.draw(in: NSRect(x: originX, y: originY, width: glyphSize.width, height: glyphSize.height))
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
// `bind(to:)` is `@MainActor` because `VoiceInkEngine` is main-actor-isolated
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
    func bind(to engine: VoiceInkEngine) {
        stateCancellable?.cancel()
        // CombineLatest3: engine recording state + hands-free session state +
        // view-side HaloPhase. Precedence inside IconState's combined init:
        // handsFree > halo view-state > engine state. Until HUD invokes
        // `bind(toHalo:)`, haloPhaseSubject stays `.hidden` and engine state
        // alone drives the icon — backward-compatible.
        stateCancellable = Publishers.CombineLatest3(
            engine.$recordingState,
            HandsFreeSessionService.shared.$state,
            haloPhaseSubject
        )
        .receive(on: DispatchQueue.main)
        .map { recordingState, handsFreeState, haloPhase in
            MenuBarIconRenderer.IconState(
                handsFree: handsFreeState,
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

// MARK: - MenuBarIcon (SwiftUI label for MenuBarExtra)
//
// Hosts MenubarGlyphContainer — pure-SwiftUI Canvas/Path mark with state
// overlays driven by TimelineView (Path A, spec §5.4 single-path commitment).
// The struct signature is preserved so VoiceInk.swift's MenuBarExtra label
// closure mounts it unchanged.
//
// Failure-registry overlay (red corner dot) composites at this layer so it
// can stack with any non-fail state.

struct MenuBarIcon: View {
    @ObservedObject var observer: RecordingStateObserver

    var body: some View {
        // MenuBarExtra rasterises its label into the status-item button image
        // on every SwiftUI update. A TimelineView-driven label (the animated
        // MenubarGlyphContainer) re-rasterises every animation frame, pinning
        // the main thread in an infinite updateButton -> setImage -> _adjustLength
        // loop (100% CPU, app hang). Render a static per-state NSImage instead:
        // it re-evaluates only when iconState or unresolvedFailures changes.
        Image(nsImage: MenuBarIconRenderer.image(
            for: observer.iconState,
            unresolvedFailures: observer.unresolvedFailures
        ))
        .frame(width: 18, height: 18)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        let base = MenubarGlyph.accessibilityLabel(for: observer.iconState)
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

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: MenuBarIconRenderer.image(for: state, unresolvedFailures: unresolved))
                .frame(width: 64, height: 64)

            Picker("", selection: $state) {
                Text("Idle").tag(MenuBarIconRenderer.IconState.idle)
                Text("Recording").tag(MenuBarIconRenderer.IconState.recording)
                Text("Transcribing").tag(MenuBarIconRenderer.IconState.transcribing)
                Text("Enhancing").tag(MenuBarIconRenderer.IconState.enhancing)
                Text("Hands-free").tag(MenuBarIconRenderer.IconState.handsFree)  // W12.D
            }
            .pickerStyle(.segmented)

            Stepper("Unresolved: \(unresolved)", value: $unresolved, in: 0...5)
        }
        .padding(32)
        .frame(width: 360)
    }
}

#Preview("Menu bar icon — Onyx") {
    MenuBarIconPreviewHarness()
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Menu bar icon — Light") {
    MenuBarIconPreviewHarness()
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
