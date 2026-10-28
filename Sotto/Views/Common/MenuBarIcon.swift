import AppKit
import SwiftUI

struct MenuBarIcon: View {
    @ObservedObject var observer: RecordingStateObserver
    // The idle underscore carries the accent (CapsuleState.color → Palette
    // .phosphor), resolved into a static NSImage — observe the store so an
    // accent change re-renders the image.
    @ObservedObject private var accent = AccentStore.shared
    @Environment(\.colorScheme) private var colorScheme
    /// The appearance the MENU BAR is actually drawing in. The bar can render
    /// dark while the system appearance is Light (a dark wallpaper under a
    /// transparent bar); the brand glyph is deliberately non-template, so
    /// macOS will not invert the near-black `labelColor` mark for us and the
    /// identity would disappear. Nil until the probe reports.
    @State private var barAppearance: NSAppearance?

    private var drawingAppearance: NSAppearance? {
        barAppearance ?? NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }

    var body: some View {
        // Static per-state NSImage. A SwiftUI/TimelineView label re-rasterises
        // every frame inside MenuBarExtra and pins the main thread (see commit
        // history) — so the icon is a discrete image, re-rendered only when
        // iconState/unresolvedFailures/accent change. The `.id` rebuilds it
        // on a light/dark flip or accent swap; the brand glyph is non-template
        // and image(for:) re-resolves colors each rebuild.
        Image(nsImage: MenuBarIconRenderer.image(
            for: observer.iconState,
            unresolvedFailures: observer.unresolvedFailures,
            appearance: drawingAppearance
        ))
        .frame(width: 18, height: 18)
        .overlay(
            EffectiveAppearanceReader { barAppearance = $0 }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
        .id("\(barAppearance?.name.rawValue ?? "\(colorScheme)")-\(accent.choice.rawValue)")
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

// MARK: - EffectiveAppearanceReader
//
// Reports the appearance the HOSTING view is drawing in — for a MenuBarExtra
// label that is the menu bar's own appearance, which is the only thing that
// decides whether the non-template icon is legible. Reports on attach and on
// every appearance change, so a wallpaper-driven flip propagates live.

private struct EffectiveAppearanceReader: NSViewRepresentable {
    let onChange: (NSAppearance) -> Void

    func makeNSView(context: Context) -> NSView { ProbeView(onChange: onChange) }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ProbeView)?.onChange = onChange
    }

    private final class ProbeView: NSView {
        var onChange: (NSAppearance) -> Void

        init(onChange: @escaping (NSAppearance) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            report()
        }

        private func report() {
            guard window != nil else { return }
            let matched = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
            guard let appearance = NSAppearance(named: matched) else { return }
            // The SwiftUI state write must not land inside the view update
            // that installed this probe.
            DispatchQueue.main.async { [onChange] in onChange(appearance) }
        }
    }
}
