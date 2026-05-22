import SwiftUI
import KeyboardShortcuts

struct EnhancementShortcutsView: View {
    var body: some View {
        VStack(spacing: 8) {
            // Toggle AI Enhancement
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 4) {
                    Text("Toggle AI Enhancement")
                        .font(.system(size: 13))

                    InfoTip(
                        "Quickly enable or disable AI enhancement while recording. Available only when Sotto is running and the recorder is visible.",
                        learnMoreURL: "https://tryvoiceink.com/docs/enhancement-shortcuts"
                    )
                }

                Spacer()

                KeyboardShortcuts.Recorder(for: .toggleEnhancement)
                    .controlSize(.small)
            }

            // Switch Enhancement Prompt
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 4) {
                    Text("Switch Enhancement Prompt")
                        .font(.system(size: 13))

                    InfoTip(
                        "Switch between your saved prompts using ⌘1 through ⌘0 to activate the corresponding prompt in the order they are saved. Available only when Sotto is running and the recorder is visible.",
                        learnMoreURL: "https://tryvoiceink.com/docs/enhancement-shortcuts"
                    )
                }

                Spacer()

                HStack(spacing: 4) {
                    KeyChip(label: "⌘")
                    KeyChip(label: "1 – 0")
                }
            }
        }
        .background(Color.clear)
    }
}

// MARK: - Supporting Views
private struct KeyChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 0.078, green: 0.078, blue: 0.110).opacity(0.55))
                    .background(
                        TacticalGlass(
                            shape: RoundedRectangle(cornerRadius: 6, style: .continuous),
                            phase: .hidden
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
    }
}
