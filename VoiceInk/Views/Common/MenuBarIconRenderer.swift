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
                color: NSColor(Palette.accent),
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
        Image(nsImage: MenuBarIconRenderer.image(for: observer.iconState))
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

// MARK: - Previews

#if DEBUG
private struct MenuBarIconPreviewHarness: View {
    @State private var state: MenuBarIconRenderer.IconState = .idle

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: MenuBarIconRenderer.image(for: state))
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
