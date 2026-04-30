import SwiftUI
import SwiftData

/// W12.C voice-snippets settings surface. CRUD over `Snippet` SwiftData
/// records. See plan `docs/superpowers/plans/W12C-voice-snippets.md` §T5.
struct SnippetsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Snippet.createdAt, order: .forward) private var snippets: [Snippet]
    @State private var editorSnippet: Snippet? = nil
    @State private var showingAddSheet: Bool = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                snippetsCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .adaptiveGlassBackground()
        .sheet(isPresented: $showingAddSheet) {
            SnippetEditorSheet(
                editing: nil,
                existingSnippets: snippets,
                onSave: addSnippet,
                onCancel: { showingAddSheet = false }
            )
        }
        .sheet(item: $editorSnippet) { snippet in
            SnippetEditorSheet(
                editing: snippet,
                existingSnippets: snippets,
                onSave: { updated in updateSnippet(snippet, with: updated); editorSnippet = nil },
                onCancel: { editorSnippet = nil }
            )
        }
    }

    private var snippetsCard: some View {
        SettingsCard(
            iconSystemName: "text.cursor",
            iconTint: Palette.accent,
            title: "Snippets",
            subtitle: "Type a trigger; speak it; expand it.",
            statusText: snippets.isEmpty ? "Empty" : "\(snippets.count) defined",
            statusTone: snippets.isEmpty ? .neutral : .positive
        ) {
            if snippets.isEmpty {
                Text("Add your first snippet to expand triggers like `;sig` into long-form text.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snippets) { snippet in
                        snippetRow(snippet)
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            }
        }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        SettingsRow(
            iconSystemName: snippet.isEnabled ? "checkmark.circle" : "circle.slash",
            label: snippet.trigger,
            subtitle: previewExpansion(snippet.expansion),
            iconTint: snippet.isEnabled ? Palette.success : Palette.neutral
        ) {
            HStack(spacing: 8) {
                Toggle("", isOn: bindingForEnabled(snippet)).labelsHidden()
                Button {
                    editorSnippet = snippet
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) {
                    deleteSnippet(snippet)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func previewExpansion(_ expansion: String) -> String {
        let trimmed = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 60 { return trimmed }
        return String(trimmed.prefix(57)) + "..."
    }

    private func bindingForEnabled(_ snippet: Snippet) -> Binding<Bool> {
        Binding(
            get: { snippet.isEnabled },
            set: { newValue in
                snippet.isEnabled = newValue
                snippet.updatedAt = Date()
                try? modelContext.save()
                SnippetExpansionService.shared.invalidateCache()
            }
        )
    }

    private func addSnippet(_ candidate: Snippet) {
        modelContext.insert(candidate)
        try? modelContext.save()
        SnippetExpansionService.shared.invalidateCache()
        showingAddSheet = false
    }

    private func updateSnippet(_ existing: Snippet, with candidate: Snippet) {
        existing.trigger = candidate.trigger
        existing.expansion = candidate.expansion
        existing.tags = candidate.tags
        existing.isEnabled = candidate.isEnabled
        existing.updatedAt = Date()
        try? modelContext.save()
        SnippetExpansionService.shared.invalidateCache()
    }

    private func deleteSnippet(_ snippet: Snippet) {
        modelContext.delete(snippet)
        try? modelContext.save()
        SnippetExpansionService.shared.invalidateCache()
    }
}
