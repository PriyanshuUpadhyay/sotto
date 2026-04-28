import SwiftUI
import UniformTypeIdentifiers

struct EnhancementSettingsView: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @State private var isEditingPrompt = false
    @State private var isShowingSettings = false
    @State private var selectedPromptForEdit: CustomPrompt?
    @State private var panelID = UUID()

    /// Settings sliding panel — narrow form (toggles + selectors).
    private let settingsPanelWidth: CGFloat = 400
    /// Prompt-editor sliding panel — wider to host the 50/50 split (editor +
    /// live preview, spec §3.9 / plan §P3.E).
    private let promptEditorPanelWidth: CGFloat = 880

    /// Active panel's width. Drives the `slidingPanel` modifier so the
    /// settings panel stays compact while the prompt editor gets room for
    /// the split layout.
    private var currentPanelWidth: CGFloat {
        activePanel == .promptEditor ? promptEditorPanelWidth : settingsPanelWidth
    }

    private enum PanelType {
        case promptEditor
        case settings
    }

    private var activePanel: PanelType? {
        if isShowingSettings { return .settings }
        if isEditingPrompt || selectedPromptForEdit != nil { return .promptEditor }
        return nil
    }

    private var isPanelOpen: Bool {
        activePanel != nil
    }

    private func openPromptPanel() {
        isShowingSettings = false
        panelID = UUID()
    }

    private func closePanel() {
        withAnimation(.smooth(duration: 0.3)) {
            isEditingPrompt = false
            selectedPromptForEdit = nil
            isShowingSettings = false
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enhancementService.isEnhancementEnabled) {
                    HStack(spacing: 4) {
                        Text("Enable Enhancement")
                        InfoTip(
                            "AI enhancement lets you pass the transcribed audio through LLMs to post-process using different prompts suitable for different use cases like e-mails, summary, writing, etc.",
                            learnMoreURL: "https://tryvoiceink.com/docs/enhancements-configuring-models"
                        )
                    }
                }
                .toggleStyle(.switch)
            } header: {
                HStack(alignment: .top, spacing: 12) {
                    SettingsSectionHeader(
                        icon: "wand.and.stars",
                        title: "Enhancement",
                        subtitle: "Pass transcripts through an LLM before pasting.",
                        accent: Palette.accent,
                        statusText: enhancementService.isEnhancementEnabled ? "On" : "Off",
                        statusTone: enhancementService.isEnhancementEnabled ? .positive : .neutral
                    )
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            isEditingPrompt = false
                            selectedPromptForEdit = nil
                            isShowingSettings.toggle()
                        }
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isShowingSettings ? Palette.accent : .secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Palette.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Enhancement settings")
                }
            }

            APIKeyManagementView()
                .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)

            Section {
                ReorderablePromptGrid(
                    selectedPromptId: enhancementService.selectedPromptId,
                    onPromptSelected: { prompt in
                        enhancementService.setActivePrompt(prompt)
                    },
                    onEditPrompt: { prompt in
                        openPromptPanel()
                        withAnimation(.smooth(duration: 0.3)) {
                            selectedPromptForEdit = prompt
                        }
                    },
                    onDeletePrompt: { prompt in
                        enhancementService.deletePrompt(prompt)
                    }
                )
                .padding(.vertical, 8)
            } header: {
                HStack(alignment: .top, spacing: 12) {
                    SettingsSectionHeader(
                        icon: "text.bubble",
                        title: "Enhancement Prompts",
                        subtitle: "Pick the active style; reorder by drag.",
                        accent: Palette.accent,
                        statusText: "\(enhancementService.customPrompts.count)",
                        statusTone: .neutral
                    )
                    Button {
                        openPromptPanel()
                        withAnimation(.smooth(duration: 0.3)) {
                            isEditingPrompt = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Palette.accent)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Palette.accent.opacity(0.14))
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(.ultraThinMaterial)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Palette.accent.opacity(0.42), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Add new prompt")
                }
            }
            .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .adaptiveGlassBackground()
        .slidingPanel(isPresented: .init(
            get: { isPanelOpen },
            set: { newValue in
                if !newValue { closePanel() }
            }
        ), width: currentPanelWidth) {
            Group {
                switch activePanel {
                case .settings:
                    EnhancementSettingsPanel(onDismiss: closePanel)
                case .promptEditor:
                    Group {
                        if let prompt = selectedPromptForEdit {
                            PromptEditorView(mode: .edit(prompt)) {
                                closePanel()
                            }
                        } else if isEditingPrompt {
                            PromptEditorView(mode: .add) {
                                closePanel()
                            }
                        }
                    }
                    .id(panelID)
                case nil:
                    EmptyView()
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Reorderable Grid
private struct ReorderablePromptGrid: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService

    let selectedPromptId: UUID?
    let onPromptSelected: (CustomPrompt) -> Void
    let onEditPrompt: ((CustomPrompt) -> Void)?
    let onDeletePrompt: ((CustomPrompt) -> Void)?

    @State private var draggingItem: CustomPrompt?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if enhancementService.customPrompts.isEmpty {
                Text("No prompts available")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 36)
                ]

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(enhancementService.customPrompts) { prompt in
                        prompt.promptIcon(
                            isSelected: selectedPromptId == prompt.id,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    onPromptSelected(prompt)
                                }
                            },
                            onEdit: onEditPrompt,
                            onDelete: onDeletePrompt
                        )
                        .opacity(draggingItem?.id == prompt.id ? 0.3 : 1.0)
                        .scaleEffect(draggingItem?.id == prompt.id ? 1.05 : 1.0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    draggingItem != nil && draggingItem?.id != prompt.id
                                    ? Palette.accent.opacity(0.25)
                                    : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .animation(.easeInOut(duration: 0.15), value: draggingItem?.id == prompt.id)
                        .onDrag {
                            draggingItem = prompt
                            return NSItemProvider(object: prompt.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PromptDropDelegate(
                                item: prompt,
                                prompts: $enhancementService.customPrompts,
                                draggingItem: $draggingItem
                            )
                        )
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                HStack {
                    Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Text("Double-click to edit • Right-click for more options")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Drop Delegate
private struct PromptDropDelegate: DropDelegate {
    let item: CustomPrompt
    @Binding var prompts: [CustomPrompt]
    @Binding var draggingItem: CustomPrompt?

    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem, draggingItem != item else { return }
        guard let fromIndex = prompts.firstIndex(of: draggingItem),
              let toIndex = prompts.firstIndex(of: item) else { return }

        if prompts[toIndex].id != draggingItem.id {
            withAnimation(.easeInOut(duration: 0.12)) {
                let from = fromIndex
                let to = toIndex
                prompts.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
}
