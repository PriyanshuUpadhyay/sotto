import SwiftUI

struct PredefinedPromptsView: View {
    let onSelect: (TemplatePrompt) -> Void
    
    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 18), count: 2)
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(PromptTemplates.all, id: \.title) { template in
                    PredefinedTemplateButton(prompt: template) {
                        onSelect(template)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(minWidth: 410, idealWidth: 520, maxWidth: 570, maxHeight: 440)
    }
}

struct PredefinedTemplateButton: View {
    let prompt: TemplatePrompt
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard(cornerRadius: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.accent.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Palette.accent.opacity(0.32), lineWidth: 0.5)
                            )
                            .frame(width: 42, height: 42)
                            .overlay(
                                Image(systemName: prompt.icon)
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundColor(Palette.accent)
                            )

                        Text(prompt.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }

                    Text(prompt.description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
