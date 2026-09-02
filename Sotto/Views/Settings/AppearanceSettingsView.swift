import SwiftUI

// MARK: - Appearance

/// Appearance settings: app color scheme, accent, and reduced-motion status.
/// Both user choices persist to UserDefaults and update all window roots live.
/// One card, rendered as a General section — it owns no scroll view of its own.
struct AppearanceSettingsView: View {
    @ObservedObject private var appearance = AppearanceStore.shared
    @ObservedObject private var accent = AccentStore.shared

    var body: some View {
        SettingsCard(
            iconSystemName: "paintpalette",
            iconTint: Brand.tint,
            title: "Appearance",
            subtitle: "Color scheme and accent for Sotto."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    rowLabel("Appearance")
                    Picker("Appearance", selection: $appearance.choice) {
                        ForEach(AppearanceChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }
                .padding(.vertical, 14)

                Rectangle().fill(Theme.hairline).frame(height: 1)

                HStack(alignment: .center, spacing: 16) {
                    rowLabel("Accent")
                    HStack(spacing: 18) {
                        ForEach(AccentChoice.allCases) { choice in
                            swatch(choice)
                        }
                    }
                }
                .padding(.vertical, 14)

                Rectangle().fill(Theme.hairline).frame(height: 1)

                HStack(spacing: 16) {
                    rowLabel("Reduced motion")
                    Text("FOLLOWS SYSTEM")
                        .font(.microlabel(11))
                        .tracking(0.18 * 11)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.vertical, 14)
            }
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.microlabel(11))
            .tracking(0.18 * 11)
            .foregroundStyle(Palette.inkSecondary)
            // minWidth, not width: the column keeps its rhythm at the default
            // text size and grows rather than clipping at larger ones.
            .frame(minWidth: 140, alignment: .leading)
    }

    /// 18pt dot in a ≥24pt hit target; selected = a ring in the swatch's own
    /// color, offset from the dot.
    private func swatch(_ choice: AccentChoice) -> some View {
        let isSelected = accent.choice == choice
        return VStack(spacing: 7) {
            Button {
                accent.choice = choice
            } label: {
                ZStack {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                    if isSelected {
                        Circle()
                            .strokeBorder(choice.color, lineWidth: 2)
                            .frame(width: 26, height: 26)
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel("\(choice.title) accent")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Text(choice.title.uppercased())
                .font(.microlabel(10))
                .tracking(0.12 * 10)
                .foregroundStyle(Palette.inkSecondary)
        }
    }
}
