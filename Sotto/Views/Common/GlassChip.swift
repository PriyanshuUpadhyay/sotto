import SwiftUI

// MARK: - GlassChip
//
// View modifier implementing the locked Adaptive Glass chip vocabulary
// (post-redesign 2026-04). Used across the new constellation cluster (W2),
// reskinned settings cards (W5), AI / prompt chips (W6), and any new chip
// surfaces in W3/W4/W7. Source of truth:
// `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1.
//
// Geometry (locked — do not parametrize without spec change):
//   - 28pt backdrop blur, 1.4 saturate
//   - rgba(20,20,28, 0.55) translucent fill
//   - 1px white α0.16 hairline border
//   - inset 0 1.5pt 0 white α0.22 inner highlight (top edge sheen)
//   - 0 14pt 36pt black α0.55 drop shadow
//   - 10pt corner radius (chips), 14pt for panels — caller chooses via init
//
// Reduce-Motion / fallback rendering: SwiftUI `Material` already degrades
// gracefully on older macOS or under Reduce-Transparency. No extra branch
// needed here.

struct GlassChip: ViewModifier {
    var cornerRadius: CGFloat = 10
    var paddingH: CGFloat = 11
    var paddingV: CGFloat = 7

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .background(
                shape
                    .fill(Theme.panel.opacity(0.55))
                    .background(
                        // backdrop refraction layer
                        shape.fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                shape.stroke(Theme.hairline, lineWidth: 1)
            )
            .overlay(
                // top-edge sheen (1.5pt inset highlight on the top)
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [Palette.innerHi, .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.18)
                        ),
                        lineWidth: 1.5
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 36, x: 0, y: 14)
            .clipShape(shape)
    }
}

extension View {
    /// Wraps the view in a 10pt-radius Adaptive Glass chip per spec §1.
    /// Use for state chips, action chips, status pills.
    func glassChip(cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassChip(cornerRadius: cornerRadius))
    }

    /// Wider radius (14pt) variant for panels / cards. Same vocabulary,
    /// just a softer corner.
    func glassPanel(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassChip(cornerRadius: cornerRadius, paddingH: 14, paddingV: 12))
    }
}

// MARK: - Previews

#if DEBUG
private struct GlassChipPreviewBody: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Text("REC")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.06 * 10.5)
                    .foregroundColor(Palette.inkPrimary)
                    .glassChip()
                Text("00:14")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.06 * 10.5)
                    .foregroundColor(Palette.inkSecondary)
                    .glassChip()
            }
            Text("MODEL · Parakeet → Gemma 4")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(0.06 * 11)
                .foregroundColor(Palette.inkPrimary)
                .glassPanel()
        }
        .padding(40)
    }
}

#Preview("GlassChip · onyx wallpaper") {
    GlassChipPreviewBody()
        .background(
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.10, blue: 0.34), Color(red: 0.54, green: 0.23, blue: 0.42)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
}
#endif
