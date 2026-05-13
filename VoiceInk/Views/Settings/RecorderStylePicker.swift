import SwiftUI

// MARK: - RecorderStylePicker
//
// Two visual cards — each a miniature of the corresponding recorder
// surface — instead of the old segmented "Notch / Mini" text picker.
//
// Identifier contract (matches `RecorderUIManager.recorderType`):
//   "notch"  → Halo pill in the notch
//   "mini"   → Halo pill floating top-of-screen
//
// `RecorderUIManager` branches on `"notch"` vs. `"mini"` in
// `showRecorderPanel`. A legacy `"constellation"` value (shipped briefly as
// a vaporware third tile that always fell through to mini) is migrated to
// `"mini"` on read in `RecorderUIManager.recorderType`'s initializer.

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
                    .stroke(isSelected ? Palette.brandAcid : Palette.hairlineSoft,
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
                .fill(isSelected ? Palette.brandAcid.opacity(0.06) : Color.clear)
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
                                .fill(Palette.brandAcid.opacity(0.85))
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
                    .shadow(color: Palette.brandAcid.opacity(0.45), radius: 8)
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
