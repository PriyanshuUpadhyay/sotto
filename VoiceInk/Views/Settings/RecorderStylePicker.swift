import SwiftUI

// MARK: - RecorderStylePicker
//
// Three visual cards — each a miniature of the corresponding recorder
// surface — instead of the old segmented "Notch / Mini" text picker.
// The Constellation tile previews the W2 chip cluster silhouette (anchor +
// secondaries) so users see the new vocabulary before opting in.
//
// Identifier contract (matches `RecorderUIManager.recorderType`):
//   "notch"          → Halo pill in the notch
//   "mini"           → Halo pill floating top-of-screen
//   "constellation"  → Constellation chip cluster (anchor + secondaries)
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
                subtitle: "Anchor · chips",
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
                    .stroke(isSelected ? Palette.accent : Palette.hairlineSoft,
                             lineWidth: isSelected ? 2 : 0.5)
            )

            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
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
                .fill(isSelected ? Palette.accent.opacity(0.06) : Color.clear)
        )
        .animation(Animation.haloPhaseCrossfade, value: isSelected)
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
// Static miniature of the W2 chip cluster (spec §2 + §4): anchor REC chip
// flanked by TIME (left) and PROMPT (right). Hand-painted at preview scale
// so the tile stays motion-free — Reduce Motion compliance per spec §6.4.

private struct ConstellationPreview: View {
    var body: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 6)
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                miniSecondary(text: "00:14")
                miniAnchor
                miniSecondary(text: "PROMPT")
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var miniAnchor: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Palette.accent)
                .frame(width: 4, height: 4)
                .shadow(color: Palette.accent.opacity(0.7), radius: 2)
            Text("REC")
                .font(.system(size: 5, weight: .medium, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(Color.white.opacity(0.95))
        }
        .padding(.horizontal, 4)
        .frame(height: 11)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Palette.hairline, lineWidth: 0.5)
                )
        )
    }

    private func miniSecondary(text: String) -> some View {
        Text(text)
            .font(.system(size: 5, weight: .medium, design: .monospaced))
            .tracking(0.3)
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 4)
            .frame(height: 11)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.5)
                    )
            )
    }
}
