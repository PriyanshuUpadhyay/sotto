import SwiftUI

/// W12.C add / edit modal. Validates trigger format + uniqueness on Save.
/// See plan `docs/superpowers/plans/W12C-voice-snippets.md` §T5 +
/// §Migration policy #6 + §Migration policy #13.
struct SnippetEditorSheet: View {
    let editing: Snippet?
    let existingSnippets: [Snippet]
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    @State private var trigger: String = ""
    @State private var expansion: String = ""
    @State private var tagsText: String = ""
    @State private var isEnabled: Bool = true
    @State private var inlineError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "Add Snippet" : "Edit Snippet")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Trigger")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextField(";sig", text: $trigger)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Text("Letters, numbers, and ; : _ . / @ - are allowed. 1-32 chars.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Expansion")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextEditor(text: $expansion)
                    .frame(minHeight: 120, maxHeight: 240)
                    .font(.system(.body))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tags (comma-separated, optional)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("personal, signature", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Enabled", isOn: $isEnabled)

            if let inlineError {
                Text(inlineError)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.warn)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: validateAndSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: hydrate)
    }

    private func hydrate() {
        if let editing {
            trigger = editing.trigger
            expansion = editing.expansion
            tagsText = editing.tags.joined(separator: ", ")
            isEnabled = editing.isEnabled
        }
    }

    private func validateAndSave() {
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespaces)
        let trimmedExpansion = expansion // preserve user spacing in expansion body

        if let validation = Snippet.validate(
            trigger: trimmedTrigger,
            against: existingSnippets,
            editingId: editing?.id
        ) {
            inlineError = validation.errorDescription
            return
        }
        if trimmedExpansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inlineError = "Expansion cannot be empty."
            return
        }

        let parsedTags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let snippet = Snippet(
            trigger: trimmedTrigger,
            expansion: trimmedExpansion,
            tags: parsedTags,
            isEnabled: isEnabled,
            createdAt: editing?.createdAt ?? Date(),
            updatedAt: Date()
        )
        onSave(snippet)
    }
}
