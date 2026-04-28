import SwiftUI

// MARK: - RecorderStylePicker
//
// Three visual cards — each a miniature of the corresponding recorder
// surface — instead of the old segmented "Notch / Mini" text picker.
// Per plan §P2.E, adds a third tile for the Constellation recorder so users
// can preview the orb + chip + card silhouette before opting in.
//
// Identifier contract (matches `RecorderUIManager.recorderType`):
//   "notch"          → Halo pill in the notch
//   "mini"           → Halo pill floating top-of-screen
//   "constellation"  → Constellation orb + chip + card composition
//
// `RecorderUIManager` currently branches on `"notch"` vs. everything else;
// `"constellation"` falls through to the floating layout until Phase 3 wires
// a dedicated window manager. The picker still records the user's intent
// via `@AppStorage`-backed UserDefaults so the wiring lands without
// re-prompting the user.

struct RecorderStylePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 14) {
            RecorderStyleCard(
                title: "Halo (Notch)",
                subtitle: "Top, fits the notch",
                identifier: "notch",
                isSelected: selection == "notch",
                preview: { NotchPreview() }
            )
            .onTapGesture { selection = "notch" }

            RecorderStyleCard(
                title: "Halo (Floating)",
                subtitle: "Top-anchored pill",
                identifier: "mini",
                isSelected: selection == "mini",
                preview: { FloatingPreview() }
            )
            .onTapGesture { selection = "mini" }

            RecorderStyleCard(
                title: "Constellation",
                subtitle: "Orb · chip · card",
                identifier: "constellation",
                isSelected: selection == "constellation",
                preview: { ConstellationPreview() }
            )
            .onTapGesture { selection = "constellation" }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// MARK: - Card

private struct RecorderStyleCard<Preview: View>: View {
    let title: String
    let subtitle: String
    let identifier: String
    let isSelected: Bool
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Wallpaper-ish gradient backdrop so the dark pill reads against something.
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.18, blue: 0.24),
                        Color(red: 0.08, green: 0.10, blue: 0.16)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                preview()
            }
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Palette.accent : Color.white.opacity(0.12),
                             lineWidth: isSelected ? 2 : 0.5)
            )

            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 150)
        .padding(8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Notch preview

private struct NotchPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            // Mini menu bar
            HStack(spacing: 4) {
                Circle().fill(Color.white.opacity(0.5)).frame(width: 3, height: 3)
                Circle().fill(Color.white.opacity(0.5)).frame(width: 3, height: 3)
                Spacer()
                ZStack {
                    HaloShape(mode: .notch, topCornerRadius: 4, bottomCornerRadius: 8)
                        .fill(Color.black)
                        .frame(width: 56, height: 14)
                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { i in
                            Capsule()
                                .fill(Palette.accent.opacity(0.85))
                                .frame(width: 1.5, height: CGFloat(3 + i % 3 * 2))
                        }
                    }
                }
                Spacer()
                Circle().fill(Color.white.opacity(0.5)).frame(width: 3, height: 3)
            }
            .padding(.horizontal, 8)
            .frame(height: 14)
            .background(Color.white.opacity(0.03))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Floating preview

private struct FloatingPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 8)
            ZStack {
                Capsule()
                    .fill(Color.black)
                    .frame(width: 70, height: 16)
                    .shadow(color: Palette.accent.opacity(0.45), radius: 8)
                HStack(spacing: 1.5) {
                    ForEach(0..<7, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 1.6, height: CGFloat(3 + (i * 7 % 5)))
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Constellation preview
//
// Static miniature of the real Constellation recorder (spec §3.1):
//   • Orb (accent @ .recording)  — small filled circle with white@0.25 ring
//     + dual color glows, mirroring `ConstellationOrb` at the recording phase.
//   • Chip — capsule with leading color dot + mono `CLAUDE · SONNET` label,
//     mirroring `ConstellationChip` proportions.
//   • Card — rounded glass plaque below with placeholder transcript line,
//     mirroring `ConstellationCard` at the recording phase.
//
// Hand-painted (not the real primitives) so the tile stays static — the live
// `ConstellationOrb` would pulse / breathe; spec §6.4 requires Reduce Motion
// honored for any tile micro-animation. By rendering everything as plain
// static shapes here we side-step the issue entirely (no motion tokens
// active inside the tile preview).
//
// Reviewer focus (plan §P2.E): the layout is recognizably "orb + chip + card"
// — not a placeholder rectangle. Same three-piece silhouette as the
// production recorder, just shrunk to fit the 84pt-tall preview viewport.

private struct ConstellationPreview: View {
    var body: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 6)

            // Top row — orb + chip, mirroring the production layout where the
            // chip sits to the right of the orb.
            HStack(alignment: .center, spacing: 6) {
                Spacer(minLength: 0)
                miniOrb
                miniChip
                Spacer(minLength: 0)
            }

            // Card — sits below the orb/chip pair, ~half the tile width.
            miniCard

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Miniature `ConstellationOrb` at `.recording`: 8pt tangerine disc with
    /// white halo ring + dual accent glows.
    private var miniOrb: some View {
        ZStack {
            Circle()
                .fill(Palette.accent)
                .frame(width: 8, height: 8)
                .shadow(color: Palette.accent.opacity(0.85), radius: 4)
                .shadow(color: Palette.accent.opacity(0.50), radius: 8)
            Circle()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                .frame(width: 12, height: 12)
        }
        .frame(width: 14, height: 14)
    }

    /// Miniature `ConstellationChip`: 11pt-tall dark capsule with leading
    /// red dot + mono label. Provider/model abbreviated to fit ~32pt width.
    private var miniChip: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Palette.accent)
                .frame(width: 3, height: 3)
            Text("CLAUDE")
                .font(.system(size: 5, weight: .medium, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(.horizontal, 4)
        .frame(height: 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.78))
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                )
        )
        .shadow(color: Palette.accent.opacity(0.30), radius: 4)
    }

    /// Miniature `ConstellationCard`: rounded glass plaque with two faint
    /// transcript lines, mirroring the recording-phase card content.
    private var miniCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Capsule()
                .fill(Color.white.opacity(0.55))
                .frame(width: 38, height: 2)
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 24, height: 2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: 56, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 3, y: 2)
    }
}
