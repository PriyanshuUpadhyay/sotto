import SwiftUI

struct FillerWordChip: View {
    let word: String
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(word)
                .font(.ui(12))
                .foregroundColor(.primary)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isHovered ? Palette.warn : .secondary)
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .onHover { hover in
                withAnimation(Animation.haloPhaseCrossfade) {
                    isHovered = hover
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
    }
}

struct FillerWordsSettingsView: View {
    @AppStorage("RemoveFillerWords") private var removeFillerWords = true
    @StateObject private var fillerWordManager = FillerWordManager.shared
    @State private var newWord = ""
    @State private var showDuplicateAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Remove filler words")
                InfoTip("Automatically remove filler words like 'uh', 'um', 'hmm' from transcriptions.")
                Spacer()
                Toggle("", isOn: $removeFillerWords)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if removeFillerWords {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Add filler word", text: $newWord)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addWord() }

                        Button(action: addWord) {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Brand.tint)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(.borderless)
                        .help("Add filler word")
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.vertical, 4)

                    if !fillerWordManager.fillerWords.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(fillerWordManager.fillerWords, id: \.self) { word in
                                FillerWordChip(word: word) {
                                    withAnimation(Animation.haloPhaseCrossfade) {
                                        fillerWordManager.removeWord(word)
                                    }
                                }
                            }
                        }
                    }

                }
                .padding(.leading, 4)
            }
        }
        .alert("Duplicate Word", isPresented: $showDuplicateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This filler word is already in the list.")
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if fillerWordManager.addWord(trimmed) {
            newWord = ""
        } else {
            showDuplicateAlert = true
        }
    }
}
