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

    /// Icon state — derived from `RecordingState`. Collapses transient app
    /// states (.starting / .busy) to `.idle`. Failure overlay is rendered
    /// separately via `image(for:unresolvedFailures:)` driven by
    /// `FailureRegistry.unresolvedCount`.
    enum IconState: Equatable {
        case idle
        case recording
        case transcribing
        case enhancing
        case handsFree  // W12.D

        init(_ state: RecordingState) {
            switch state {
            case .recording:    self = .recording
            case .transcribing: self = .transcribing
            case .enhancing:    self = .enhancing
            default:            self = .idle
            }
        }

        /// W12.D: hands-free overrides the inner recording state — when
        /// active, the user wants to see "I'm in hands-free" regardless of
        /// whether the recorder is currently capturing or committing.
        init(handsFree: HandsFreeSessionState, recordingState: RecordingState) {
            if handsFree != .inactive {
                self = .handsFree
            } else {
                self.init(recordingState)
            }
        }
    }

    static func image(for state: IconState) -> NSImage {
        switch state {
        case .idle:
            return template("waveform", weight: .light, label: "VoiceInk idle")
        case .recording:
            return tinted(
                "waveform",
                weight: .semibold,
                color: NSColor(Palette.accent),
                label: "VoiceInk recording"
            )
        case .transcribing:
            return template("waveform", weight: .regular, label: "VoiceInk transcribing")
        case .enhancing:
            return template("sparkles", weight: .regular, label: "VoiceInk enhancing")
        case .handsFree:  // W12.D
            return tinted(
                "ear.fill",
                weight: .semibold,
                color: NSColor(Palette.accent),
                label: "VoiceInk hands-free"
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
        switch state {
        case .recording:    return "VoiceInk recording, \(suffix)"
        case .transcribing: return "VoiceInk transcribing, \(suffix)"
        case .enhancing:    return "VoiceInk enhancing, \(suffix)"
        case .idle:         return "VoiceInk idle, \(suffix)"
        case .handsFree:    return "VoiceInk hands-free, \(suffix)"
        }
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

    @MainActor
    func bind(to engine: VoiceInkEngine) {
        stateCancellable?.cancel()
        // W12.D: combine engine recording state with hands-free session state
        // so the menubar reflects "I'm in hands-free" whenever the session is
        // active, regardless of inner recorder phase. CombineLatest emits on
        // every change to either side; `removeDuplicates` short-circuits idle
        // re-publishes.
        stateCancellable = Publishers.CombineLatest(
            engine.$recordingState,
            HandsFreeSessionService.shared.$state
        )
        .receive(on: DispatchQueue.main)
        .map { recordingState, handsFreeState in
            MenuBarIconRenderer.IconState(
                handsFree: handsFreeState,
                recordingState: recordingState
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

    deinit {
        stateCancellable?.cancel()
        registryCancellable?.cancel()
    }
}

// MARK: - MenuBarIcon (SwiftUI label for MenuBarExtra)
//
// SwiftUI primitive — `Image(nsImage:)` so SwiftUI's `MenuBarExtra` snapshot
// extraction picks up a real glyph. (`NSViewRepresentable` labels render as a
// 0-size hot zone with no visible glyph in `.menuBarExtraStyle(.window)`.)
// State swaps are immediate; per spec §3.11 the menu bar icon is a passive
// indicator — the loud animation lives on the morphing recorder pill.

struct MenuBarIcon: View {
    @ObservedObject var observer: RecordingStateObserver

    var body: some View {
        Image(
            nsImage: MenuBarIconRenderer.image(
                for: observer.iconState,
                unresolvedFailures: observer.unresolvedFailures
            )
        )
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        let base: String = {
            switch observer.iconState {
            case .idle:         return "VoiceInk idle"
            case .recording:    return "VoiceInk recording"
            case .transcribing: return "VoiceInk transcribing"
            case .enhancing:    return "VoiceInk enhancing"
            case .handsFree:    return "VoiceInk hands-free"
            }
        }()
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
