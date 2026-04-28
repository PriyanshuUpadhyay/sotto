import SwiftUI

// MARK: - PowerModeActivePill (P2.H / spec §3.12)
//
// Compact glass chip rendered alongside the constellation card during active
// recorder states (recording / liveText / transcribing / enhancing) when a
// Power Mode is matched. Reads `PowerModeManager.activeConfiguration`.
//
// Layout: emoji (12pt) + name (mono caps 9pt) + small Palette.warn dot.
//
// Motion (spec §3.12):
//   • 220ms cross-fade on mount / when the matched mode flips. Encoded via
//     `id(config.id)` + `.transition(.opacity)` driven from the orchestrator.
//   • Reduce Motion → fade collapses to instant swap (transition still uses
//     opacity, but `Animation.haloPhaseCrossfade` honors Reduce Motion via
//     the orchestrator's animation context).
//
// The constellation NSPanel is configured with `ignoresMouseEvents = true`
// (see ConstellationContainer header). The pill therefore renders as visual
// chrome only — `onTap` is plumbed for future surfaces (Settings strip /
// menu bar) but is a no-op when hosted in the recorder panel.

struct PowerModeActivePill: View {
    let emoji: String
    let name: String
    var appearance: GlassAppearance = .onyx
    var onTap: (() -> Void)? = nil

    var body: some View {
        let shape = Capsule(style: .continuous)
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 12))

                Text(name.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120, alignment: .leading)

                Circle()
                    .fill(Palette.warn)
                    .frame(width: 5, height: 5)
                    .shadow(color: Palette.warn.opacity(0.55), radius: 2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                HaloMaterial(
                    shape: shape,
                    phase: .hidden,
                    appearance: appearance
                )
            )
            .overlay(
                shape.stroke(Palette.warn.opacity(0.32), lineWidth: 0.5)
            )
            .clipShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Active Power Mode: \(name)")
    }
}

#if DEBUG
#Preview("Onyx") {
    VStack(spacing: 16) {
        PowerModeActivePill(emoji: "💼", name: "Work", appearance: .onyx)
        PowerModeActivePill(emoji: "✏️", name: "Cursor", appearance: .onyx)
    }
    .padding(40)
    .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Light") {
    VStack(spacing: 16) {
        PowerModeActivePill(emoji: "💼", name: "Work", appearance: .light)
        PowerModeActivePill(emoji: "✏️", name: "Cursor", appearance: .light)
    }
    .padding(40)
    .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
