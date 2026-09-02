import SwiftUI
import AppKit

// MARK: - AppKitGlassCapsule
//
// The recording pill's material, taken off SwiftUI's `.glassEffect` and onto
// AppKit's `NSGlassEffectView`. Same platform Liquid Glass, but the AppKit view
// takes the content as its `contentView`, so the lens is built around the pill
// rather than mapped onto it — which is what finally frosted on device. Every
// SwiftUI variant (regular, clear, tints, a vibrant appearance) read as a flat
// slab in the strip window; measured on a dark desktop the untinted lens sat
// within a few luminance points of its own backdrop.
//
// Only the capsule uses this. The review editor, the ping, the palette and the
// quick-add panel are large enough for the SwiftUI lens and stay on
// `SottoGlass`; so does this surface's own Reduce Transparency / Increase
// Contrast fallback, which is `SottoGlassBackground`'s opaque matte, unchanged.

/// Hosts `content` inside an `NSGlassEffectView` and sizes itself to the
/// content's fitting size, so the pill still grows and shrinks with the tape.
struct AppKitGlassCapsule<Content: View>: NSViewRepresentable {
    /// Stained-glass tint for a terminal state, composited over the lift.
    let tint: Color?
    @ViewBuilder let content: Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CapsuleGlassView {
        let host = NSHostingView(rootView: content)
        context.coordinator.host = host
        let view = CapsuleGlassView()
        view.style = .regular
        view.contentView = host
        view.host = host
        applyTint(to: view)
        return view
    }

    func updateNSView(_ view: CapsuleGlassView, context: Context) {
        // The mic bars redraw inside the hosted graph at the meter's rate and
        // never reach this call; what does reach it is a state or tape change,
        // so it stays a root swap and a colour write.
        context.coordinator.host?.rootView = content
        applyTint(to: view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: CapsuleGlassView,
                      context: Context) -> CGSize? {
        context.coordinator.host?.fittingSize
    }

    final class Coordinator {
        var host: NSHostingView<Content>?
    }

    private func applyTint(to view: CapsuleGlassView) {
        guard let tint else {
            view.tintColor = Palette.glassCapsuleLift
            return
        }
        view.tintColor = NSColor(tint)
    }
}

/// Keeps the lens a capsule at whatever height the content settles on, and
/// keeps the hosted content filling it.
final class CapsuleGlassView: NSGlassEffectView {
    var host: NSView?

    override func layout() {
        super.layout()
        cornerRadius = bounds.height / 2
        host?.frame = bounds
    }
}

// MARK: - Rim gloss
//
// `NSGlassEffectView` lights its own silhouette, but at 38pt the rim it draws
// is below the noise of a busy desktop — next to a Control Center module the
// pill had no edge at all. This is the hairline INSIDE that edge, not a stroke
// around it: top-lit, so it reads as a specular highlight running along the top
// and a softer return along the bottom, and it opposes the appearance
// (`Palette.glassRim*`), never a flat opaque line.

struct CapsuleRimGloss: View {
    var body: some View {
        Capsule().strokeBorder(
            LinearGradient(
                stops: [
                    .init(color: Palette.glassRimTop, location: 0),
                    .init(color: Palette.glassRimTop.opacity(0.45), location: 0.40),
                    .init(color: Palette.glassRimBottom.opacity(0.55), location: 0.60),
                    .init(color: Palette.glassRimBottom, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            ),
            lineWidth: 1
        )
        .allowsHitTesting(false)
    }
}

extension View {
    /// The recording pill's surface: the AppKit lens plus its rim, collapsing
    /// to the shared opaque matte under Reduce Transparency / Increase
    /// Contrast exactly as `.sottoGlass(.capsule,...)` does.
    func sottoCapsuleGlass(tint: Color? = nil) -> some View {
        modifier(SottoCapsuleGlass(tint: tint))
    }
}

struct SottoCapsuleGlass: ViewModifier {
    let tint: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .sottoGlass(.capsule, in: Capsule(), tint: tint)
                .clipShape(Capsule())
        } else {
            AppKitGlassCapsule(tint: tint) {
                content
                    .overlay(CapsuleRimGloss())
                    // The hosted content is a SEPARATE SwiftUI graph. It reads
                    // the accessibility settings from the system itself, but a
                    // scheme a caller FORCED (the preview, the snapshot
                    // harness) only lives in the environment, so it is handed
                    // across by hand.
                    .environment(\.colorScheme, colorScheme)
            }
        }
    }
}
