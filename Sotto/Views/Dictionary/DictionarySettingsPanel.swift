import SwiftUI
import KeyboardShortcuts

struct DictionarySettingsPanel: View {
    @AppStorage("autoLearnVocabulary") private var autoLearnVocabulary: Bool = true
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("Dictionary Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.inkPrimary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Palette.mtRaise2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Palette.mtLine, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Palette.mtRaise)
            .overlay(
                Rectangle()
                    .fill(Palette.mtLine)
                    .frame(height: 1),
                alignment: .bottom
            )

            // Content
            Form {
                Section {
                    Toggle(isOn: $autoLearnVocabulary) {
                        HStack(spacing: 4) {
                            Text("Auto Learn Vocabulary")
                            InfoTip("Automatically adds corrected words to your vocabulary when you edit a transcription after pasting. This feature is experimental and may not work perfectly.")
                        }
                    }
                    .toggleStyle(.switch)
                } header: {
                    HStack(spacing: 6) {
                        Text("Auto Learn")
                        HStack(spacing: 3) {
                            Image(systemName: "flask")
                                .font(.system(size: 8, weight: .medium))
                            Text("Experimental")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.mtRaise2)
                        .clipShape(Capsule())
                    }
                }

                Section {
                    LabeledContent("Quick Add to Dictionary") {
                        KeyboardShortcuts.Recorder(for: .quickAddToDictionary)
                            .controlSize(.small)
                    }
                } header: {
                    Text("Shortcuts")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.canvas)
    }
}
