import SwiftUI

// MARK: - GlassCard
//
// Generic glass surface used across Phase 2/3 surfaces (Menu Bar, Settings,
// AI Models, Prompts, History detail). Composes `HaloMaterial`
// at `phase: .hidden` — never duplicates the layered material itself.
//
// Hover lift removed per spec §5#8 ("GlassCard hover-lift removed (kept
// hover, dropped 4pt translate-y)"). The `@State hovering` + `.onHover`
// hook is retained so future surfaces can opt into a non-translate hover
// signal (e.g. accent-glow swell) without rewiring the boolean. Matches
// W6's `ProviderCard` migration pattern.
//
// Appearance defaults to `GlassAppearanceDetector.shared.current` when nil.
// Callers may pin `appearance: .onyx` / `.light` for surfaces that should not
// adapt to wallpaper luminance (e.g. fixed dark recorder satellites).

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 14
    var appearance: GlassAppearance? = nil
    @ViewBuilder let content: () -> Content

    @ObservedObject private var detector = GlassAppearanceDetector.shared
    @State private var hovering: Bool = false

    private var resolvedAppearance: GlassAppearance {
        appearance ?? detector.current
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content()
            .padding(padding)
            .background(
                HaloMaterial(
                    shape: shape,
                    phase: .hidden,
                    appearance: resolvedAppearance
                )
            )
            .onHover { hovering = $0 }
    }
}

// MARK: - Previews

#if DEBUG
private struct GlassCardPreviewBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recording")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Text("Trigger and capture audio.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Onyx — rest + hover") {
    VStack(spacing: 24) {
        GlassCard(appearance: .onyx) { GlassCardPreviewBody() }
            .frame(width: 280)
        GlassCard(appearance: .onyx) { GlassCardPreviewBody() }
            .frame(width: 280)
    }
    .padding(40)
    .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Light — rest + hover") {
    VStack(spacing: 24) {
        GlassCard(appearance: .light) { GlassCardPreviewBody() }
            .frame(width: 280)
        GlassCard(appearance: .light) { GlassCardPreviewBody() }
            .frame(width: 280)
    }
    .padding(40)
    .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
