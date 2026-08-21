import SwiftUI

// MARK: - SettingsRow
//
// Rich row layout used inside `SettingsCard` content slots. Drop-in
// replacement for `LabeledContent("Label") { control }` from the v1 Form
// layout per spec §3.3.
//
// Layout:
//   [16pt icon tile w/ section accent] [13pt label + optional 11pt subtitle]
//   [Spacer] [control]
//
// Icon tile dimensions per plan §P2.D + spec §3.3 — 16pt row tile sits beneath
// the 28pt section-header tile, establishing the row as visually secondary.
//
// VoiceOver: icon-tile + label + subtitle merge into one announcement via
// `.accessibilityElement(children: .combine)`; the control stays
// independently focusable so toggle / picker / hotkey-recorder semantics
// (value, increment, etc.) are preserved untouched.

struct SettingsRow<Control: View>: View {
    let iconSystemName: String
    let label: String
    var subtitle: String? = nil
    let iconTint: Color
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Label group — merged for VoiceOver into a single announcement.
            HStack(alignment: .center, spacing: 12) {
                iconTile
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Palette.inkPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(iconTint.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(iconTint.opacity(0.32), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: iconSystemName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(iconTint)
            )
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#if DEBUG
private struct SettingsRowPreviewBody: View {
    @State private var toggleA = true
    @State private var toggleB = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsRow(
                iconSystemName: "1.circle",
                label: "Shortcut 1",
                subtitle: "Hold to record, release to send.",
                iconTint: Brand.tint
            ) {
                Text("⌘⇧V")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            SettingsRow(
                iconSystemName: "speaker.wave.2.fill",
                label: "Sound Feedback",
                iconTint: Brand.tint
            ) {
                Toggle("", isOn: $toggleA).labelsHidden()
            }

            SettingsRow(
                iconSystemName: "power",
                label: "Launch at Login",
                iconTint: Palette.success
            ) {
                Toggle("", isOn: $toggleB).labelsHidden()
            }
        }
        .padding(20)
    }
}

#Preview("Onyx") {
    SettingsRowPreviewBody()
        .frame(width: 480)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Light") {
    SettingsRowPreviewBody()
        .frame(width: 480)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
