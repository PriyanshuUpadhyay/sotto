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
// `Palette.recording` directly so the loudest signal in the system reads as
// red regardless of menu bar appearance.
//
// CALayer animations attach to the host NSImageView's backing layer — see
// `MenuBarIconAnimator` below. Reduce Motion → static color swap, no
// animations attached.

enum MenuBarIconRenderer {
    /// Canvas size — 18×18pt, the spec-pinned non-jitter footprint.
    static let pointSize: CGFloat = 18.0

    /// SF Symbol point size — slightly inset from the canvas so glyph weight
    /// changes don't bleed past the 18pt edge into the menu bar baseline.
    static let symbolSize: CGFloat = 14.0

    /// Icon state — derived from `RecordingState`. Collapses transient app
    /// states (.starting / .busy / .failed) to `.idle` since the menu bar
    /// is the wrong surface for failure dwell (the recorder card owns that).
    enum IconState: Equatable {
        case idle
        case recording
        case transcribing
        case enhancing

        init(_ state: RecordingState) {
            switch state {
            case .recording:    self = .recording
            case .transcribing: self = .transcribing
            case .enhancing:    self = .enhancing
            default:            self = .idle
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
                color: NSColor(Palette.recording),
                label: "VoiceInk recording"
            )
        case .transcribing:
            return template("waveform", weight: .regular, label: "VoiceInk transcribing")
        case .enhancing:
            return template("sparkles", weight: .regular, label: "VoiceInk enhancing")
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
        // Bake into a fresh 18×18 canvas so glyph metrics don't drift from
        // SF Symbol weight changes. Non-template — tint is permanent.
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

// MARK: - MenuBarIconAnimator
//
// CALayer animation wiring per spec §3.11:
//   recording    → 1.0s pulse, scale 1.0 ↔ 1.08 (transform.scale, autoreversed)
//   transcribing → 1.4s shimmer, opacity 1.0 ↔ 0.55 (CAKeyframeAnimation)
//   enhancing    → 1.6s breath glow on shadowOpacity 0 ↔ 0.55 (CABasicAnimation)
//
// Animation keys are stable per-state so re-application after re-attach (see
// `AnimatedMenuBarIconHost.Coordinator`) does not double-stack animations.

enum MenuBarIconAnimator {
    static let pulseKey = "voiceink.menubar.pulse"
    static let shimmerKey = "voiceink.menubar.shimmer"
    static let breathKey = "voiceink.menubar.breath"

    /// Strip every state-driven animation + reset shadow. Always called before
    /// re-applying to avoid stacking conflicting animations on the same layer.
    static func clear(_ layer: CALayer) {
        layer.removeAnimation(forKey: pulseKey)
        layer.removeAnimation(forKey: shimmerKey)
        layer.removeAnimation(forKey: breathKey)
        layer.shadowOpacity = 0.0
    }

    static func apply(state: MenuBarIconRenderer.IconState, to layer: CALayer, reduceMotion: Bool) {
        clear(layer)
        // Reduce Motion honors spec acceptance criteria: static color swap only.
        guard !reduceMotion else { return }
        switch state {
        case .idle:
            break
        case .recording:
            attachPulse(layer)
        case .transcribing:
            attachShimmer(layer)
        case .enhancing:
            attachBreath(layer)
        }
    }

    private static func attachPulse(_ layer: CALayer) {
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = 1.0
        anim.toValue = 1.08
        anim.duration = 0.5            // half-period → full cycle 1.0s per spec
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: pulseKey)
    }

    private static func attachShimmer(_ layer: CALayer) {
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [1.0, 0.55, 1.0]
        anim.keyTimes = [0.0, 0.5, 1.0]
        anim.duration = 1.4            // full cycle per spec
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: shimmerKey)
    }

    private static func attachBreath(_ layer: CALayer) {
        // Violet breath glow on the sparkles glyph — shadow on the host layer.
        layer.shadowColor = NSColor(Palette.enhance).cgColor
        layer.shadowRadius = 4.0
        layer.shadowOffset = .zero
        layer.shadowOpacity = 0.0
        let anim = CABasicAnimation(keyPath: "shadowOpacity")
        anim.fromValue = 0.0
        anim.toValue = 0.55
        anim.duration = 0.8            // half-period → full cycle 1.6s per spec
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: breathKey)
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
    private var cancellable: AnyCancellable?

    @MainActor
    func bind(to engine: VoiceInkEngine) {
        cancellable?.cancel()
        cancellable = engine.$recordingState
            .receive(on: DispatchQueue.main)
            .map(MenuBarIconRenderer.IconState.init)
            .removeDuplicates()
            .sink { [weak self] next in
                self?.iconState = next
            }
    }

    deinit {
        cancellable?.cancel()
    }
}

// MARK: - AnimatedMenuBarIcon (SwiftUI bridge)
//
// SwiftUI label for the `MenuBarExtra`. Hosts an `NSImageView` whose backing
// CALayer is animated by `MenuBarIconAnimator`. Subscribes to
// `RecordingStateObserver` so the image swap + animation re-apply on every
// engine state change.

struct AnimatedMenuBarIcon: View {
    @ObservedObject var observer: RecordingStateObserver
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared

    var body: some View {
        AnimatedMenuBarIconHost(
            state: observer.iconState,
            reduceMotion: motion.reduceMotion
        )
        .frame(width: MenuBarIconRenderer.pointSize, height: MenuBarIconRenderer.pointSize)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        switch observer.iconState {
        case .idle:         return "VoiceInk idle"
        case .recording:    return "VoiceInk recording"
        case .transcribing: return "VoiceInk transcribing"
        case .enhancing:    return "VoiceInk enhancing"
        }
    }
}

private struct AnimatedMenuBarIconHost: NSViewRepresentable {
    var state: MenuBarIconRenderer.IconState
    var reduceMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSImageView {
        let size = MenuBarIconRenderer.pointSize
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.image = MenuBarIconRenderer.image(for: state)
        view.wantsLayer = true
        // Clip-free so the breath glow (shadow) is visible past the bounds.
        if let layer = view.layer {
            // Anchor at center so transform.scale pulses around the glyph mid
            // rather than the bottom-left corner (NSView default).
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: size / 2, y: size / 2)
            layer.masksToBounds = false
        }
        context.coordinator.bind(view: view, state: state, reduceMotion: reduceMotion)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = MenuBarIconRenderer.image(for: state)
        context.coordinator.bind(view: nsView, state: state, reduceMotion: reduceMotion)
    }

    /// Re-attaches CALayer animations on `NSWindow.didBecomeKeyNotification`.
    ///
    /// Mitigation per plan §P2.C risk: `CAKeyframeAnimation` may detach when
    /// the underlying `NSStatusItem.button` rebuilds itself on click (menu
    /// open). Catching the key-window change re-applies the active animation
    /// so the icon never freezes mid-state. The notification observer is
    /// removed in `deinit` to avoid leaks.
    final class Coordinator: NSObject {
        private var keyObserver: NSObjectProtocol?
        private weak var hostView: NSImageView?
        private var lastState: MenuBarIconRenderer.IconState = .idle
        private var lastReduceMotion: Bool = false

        override init() {
            super.init()
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self,
                      let view = self.hostView,
                      let layer = view.layer else { return }
                MenuBarIconAnimator.apply(
                    state: self.lastState,
                    to: layer,
                    reduceMotion: self.lastReduceMotion
                )
            }
        }

        deinit {
            if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        }

        func bind(view: NSImageView, state: MenuBarIconRenderer.IconState, reduceMotion: Bool) {
            self.hostView = view
            self.lastState = state
            self.lastReduceMotion = reduceMotion
            if let layer = view.layer {
                MenuBarIconAnimator.apply(state: state, to: layer, reduceMotion: reduceMotion)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
private struct MenuBarIconPreviewHarness: View {
    @State private var state: MenuBarIconRenderer.IconState = .idle
    private let observer = RecordingStateObserver()

    var body: some View {
        VStack(spacing: 18) {
            // Force-publish the picked state without a real engine.
            AnimatedMenuBarIconHost(state: state, reduceMotion: false)
                .frame(width: 64, height: 64)

            Picker("", selection: $state) {
                Text("Idle").tag(MenuBarIconRenderer.IconState.idle)
                Text("Recording").tag(MenuBarIconRenderer.IconState.recording)
                Text("Transcribing").tag(MenuBarIconRenderer.IconState.transcribing)
                Text("Enhancing").tag(MenuBarIconRenderer.IconState.enhancing)
            }
            .pickerStyle(.segmented)
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
