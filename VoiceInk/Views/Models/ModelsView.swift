import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - ModelFilter
//
// Pill switcher for the Transcription gallery. Moved from the retired
// `ModelManagementView.swift` (W14E consolidation). Used only by ModelsView.

enum ModelFilter: String, CaseIterable, Identifiable {
    case recommended = "Recommended"
    case local = "Local"
    case cloud = "Cloud"
    case custom = "Custom"
    var id: String { self.rawValue }
}

// MARK: - ModelsView
//
// W14E — single unified Models settings pane. Replaces the legacy split
// between "AI Models" (transcription) and "Enhancement" (LLM provider /
// prompts) sidebar entries. The two surfaces are stitched into one
// ScrollView with two SF-Mono uppercase section headers ("Transcription"
// and "Enhancement"). Inner sub-tabs (Recommended/Local/Cloud/Custom) and
// the AI Provider 2-col grid are preserved unchanged. The two formerly-
// independent sliding panels (transcription gear, enhancement gear, prompt
// editor) are unified behind one enum-driven `activePanel` slot.
//
// W14A Force-MLX and W14B prewarm-AFM toggles continue to live inside
// `EnhancementSettingsPanel`'s ON-DEVICE section — no toggle moves.

struct ModelsView: View {
    // MARK: Environment / shared services

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var enhancementService: AIEnhancementService

    // MARK: Transcription state (re-homed from ModelManagementView)

    @StateObject private var customModelManager = CustomCloudModelManager.shared
    @StateObject private var whisperPrompt = WhisperPrompt()
    @ObservedObject private var warmupCoordinator = WhisperModelWarmupCoordinator.shared

    @State private var selectedFilter: ModelFilter = .recommended
    @State private var customModelToEdit: CustomCloudModel?

    // Unified delete alert for transcription model removal.
    @State private var isShowingDeleteAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var deleteActionClosure: () -> Void = {}

    // MARK: Enhancement state (re-homed from EnhancementSettingsView)

    @State private var isEditingPrompt = false
    @State private var selectedPromptForEdit: CustomPrompt?
    /// Forces a fresh PromptEditorView when reopening the editor.
    @State private var panelID = UUID()

    // MARK: Unified panel state

    private enum PanelKind {
        case transcriptionSettings
        case enhancementSettings
        case promptEditor
    }

    @State private var activePanel: PanelKind?

    /// Settings sliding panel — narrow form (toggles + selectors).
    private let narrowPanelWidth: CGFloat = 400
    /// Prompt-editor sliding panel — wider to host the 50/50 split (editor +
    /// live preview, spec §3.9 / plan §P3.E).
    private let promptEditorPanelWidth: CGFloat = 880

    private var currentPanelWidth: CGFloat {
        activePanel == .promptEditor ? promptEditorPanelWidth : narrowPanelWidth
    }

    private var isPanelOpen: Bool { activePanel != nil }

    private func closePanel() {
        withAnimation(.smooth(duration: 0.3)) {
            isEditingPrompt = false
            selectedPromptForEdit = nil
            activePanel = nil
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if SystemArchitecture.isIntelMac {
                    intelMacWarningBanner
                }

                // ─── Transcription ───
                sectionDivider("Transcription")
                VStack(alignment: .leading, spacing: 16) {
                    defaultModelCard
                    languageSelectionSection
                    availableModelsSection
                }

                // ─── Enhancement ───
                sectionDivider("Enhancement")
                    .padding(.top, 8)
                VStack(spacing: 16) {
                    enhancementCard
                    aiProviderCard
                    promptsCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 600, minHeight: 500)
        .adaptiveGlassBackground()
        .slidingPanel(isPresented: .init(
            get: { isPanelOpen },
            set: { newValue in
                if !newValue { closePanel() }
            }
        ), width: currentPanelWidth) {
            panelContent
        }
        .alert(isPresented: $isShowingDeleteAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .destructive(Text("Delete"), action: deleteActionClosure),
                secondaryButton: .cancel()
            )
        }
        .tint(Palette.accent)
    }

    // MARK: Sliding-panel content

    @ViewBuilder
    private var panelContent: some View {
        switch activePanel {
        case .transcriptionSettings:
            transcriptionSettingsPanel
        case .enhancementSettings:
            EnhancementSettingsPanel(onDismiss: closePanel)
        case .promptEditor:
            Group {
                if let prompt = selectedPromptForEdit {
                    PromptEditorView(mode: .edit(prompt)) { closePanel() }
                } else if isEditingPrompt {
                    PromptEditorView(mode: .add) { closePanel() }
                }
            }
            .id(panelID)
        case nil:
            EmptyView()
        }
    }

    private var transcriptionSettingsPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Transcription Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: closePanel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .adaptiveGlassBackground(intensity: .panel)
            .overlay(Divider().opacity(0.5), alignment: .bottom)

            ModelSettingsView(whisperPrompt: whisperPrompt)
        }
    }

    // MARK: Section divider header
    //
    // SF Mono uppercase label with a hairline rule beneath. Kept file-private
    // per W14E micro-caveat: do NOT promote to a shared component until a
    // third caller appears.

    private func sectionDivider(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text.uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundColor(Palette.onyxMute)
            Rectangle()
                .fill(Palette.hairlineSoft)
                .frame(height: 1)
        }
    }

    // MARK: Transcription — Intel banner

    private var intelMacWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)

            Text("Local models don't work reliably on Intel Macs")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))

            Spacer()

            Button(action: {
                withAnimation(Animation.haloExpand) {
                    selectedFilter = .cloud
                }
            }) {
                HStack(spacing: 4) {
                    Text("Use Cloud")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: Transcription — sections

    private var defaultModelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default Model")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(transcriptionModelManager.currentTranscriptionModel?.displayName ?? "No model selected")
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassChip(cornerRadius: 16, paddingH: 0, paddingV: 0))
        .cornerRadius(10)
    }

    private var languageSelectionSection: some View {
        LanguageSelectionView(
            transcriptionModelManager: transcriptionModelManager,
            displayMode: .full,
            whisperPrompt: whisperPrompt
        )
    }

    private var availableModelsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                // Pill switcher — Recommended / Local / Cloud / Custom.
                HStack(spacing: 12) {
                    ForEach(ModelFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            withAnimation(Animation.haloExpand) {
                                selectedFilter = filter
                                if activePanel == .transcriptionSettings {
                                    activePanel = nil
                                }
                            }
                        }) {
                            Text(filter.rawValue)
                                .font(.system(size: 14, weight: selectedFilter == filter ? .semibold : .medium))
                                .foregroundColor(selectedFilter == filter ? .primary : .primary.opacity(0.7))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .modifier(GlassChip(cornerRadius: 22, paddingH: 0, paddingV: 0))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(Palette.accent.opacity(selectedFilter == filter ? 0.5 : 0), lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Spacer()

                Button(action: {
                    withAnimation(Animation.haloExpand) {
                        if activePanel == .transcriptionSettings {
                            activePanel = nil
                        } else {
                            isEditingPrompt = false
                            selectedPromptForEdit = nil
                            activePanel = .transcriptionSettings
                        }
                    }
                }) {
                    Image(systemName: "gear")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(activePanel == .transcriptionSettings ? .accentColor : .primary.opacity(0.7))
                        .padding(12)
                        .modifier(GlassChip(cornerRadius: 22, paddingH: 0, paddingV: 0))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Palette.accent.opacity(activePanel == .transcriptionSettings ? 0.5 : 0), lineWidth: 1.5)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help("Transcription settings")
            }
            .padding(.bottom, 12)

            VStack(spacing: 12) {
                ForEach(filteredModels, id: \.id) { model in
                    let isWarming = (model as? WhisperModel).map { whisperModel in
                        warmupCoordinator.isWarming(modelNamed: whisperModel.name)
                    } ?? false

                    ModelCardView(
                        model: model,
                        fluidAudioModelManager: fluidAudioModelManager,
                        transcriptionModelManager: transcriptionModelManager,
                        isDownloaded: whisperModelManager.availableModels.contains { $0.name == model.name },
                        isCurrent: transcriptionModelManager.currentTranscriptionModel?.name == model.name,
                        downloadProgress: whisperModelManager.downloadProgress,
                        modelURL: whisperModelManager.availableModels.first { $0.name == model.name }?.url,
                        isWarming: isWarming,
                        deleteAction: {
                            if let customModel = model as? CustomCloudModel {
                                alertTitle = "Delete Custom Model"
                                alertMessage = "Are you sure you want to delete the custom model '\(customModel.displayName)'?"
                                deleteActionClosure = {
                                    customModelManager.removeCustomModel(withId: customModel.id)
                                    transcriptionModelManager.refreshAllAvailableModels()
                                }
                                isShowingDeleteAlert = true
                            } else if let downloadedModel = whisperModelManager.availableModels.first(where: { $0.name == model.name }) {
                                alertTitle = "Delete Model"
                                alertMessage = "Are you sure you want to delete the model '\(downloadedModel.name)'?"
                                deleteActionClosure = {
                                    Task {
                                        await whisperModelManager.deleteModel(downloadedModel)
                                    }
                                }
                                isShowingDeleteAlert = true
                            }
                        },
                        setDefaultAction: {
                            Task {
                                transcriptionModelManager.setDefaultTranscriptionModel(model)
                            }
                        },
                        downloadAction: {
                            if let whisperModel = model as? WhisperModel {
                                Task { await whisperModelManager.downloadModel(whisperModel) }
                            }
                        },
                        editAction: model.provider == .custom ? { customModel in
                            customModelToEdit = customModel
                        } : nil
                    )
                }

                // Import button as a card at the end of the Local list.
                if selectedFilter == .local {
                    HStack(spacing: 8) {
                        Button(action: { presentImportPanel() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Import Local Model…")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .modifier(GlassChip(cornerRadius: 16, paddingH: 0, paddingV: 0))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)

                        InfoTip(
                            "Add a custom fine-tuned whisper model to use with VoiceInk. Select the downloaded .bin file.",
                            learnMoreURL: "https://tryvoiceink.com/docs/custom-local-whisper-models"
                        )
                        .help("Read more about custom local models")
                    }
                }

                if selectedFilter == .custom {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                        Text("Only OpenAI-compatible transcription APIs are supported.")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                    AddCustomModelCardView(
                        customModelManager: customModelManager,
                        editingModel: customModelToEdit
                    ) {
                        // Refresh the models when a new custom model is added.
                        transcriptionModelManager.refreshAllAvailableModels()
                        customModelToEdit = nil
                    }
                }
            }
        }
        .padding()
    }

    private var filteredModels: [any TranscriptionModel] {
        switch selectedFilter {
        case .recommended:
            return transcriptionModelManager.allAvailableModels.filter {
                let recommendedNames = ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
                return recommendedNames.contains($0.name)
            }.sorted { model1, model2 in
                let recommendedOrder = ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
                let index1 = recommendedOrder.firstIndex(of: model1.name) ?? Int.max
                let index2 = recommendedOrder.firstIndex(of: model2.name) ?? Int.max
                return index1 < index2
            }
        case .local:
            return transcriptionModelManager.allAvailableModels.filter { $0.provider == .whisper || $0.provider == .nativeApple || $0.provider == .fluidAudio }
        case .cloud:
            return transcriptionModelManager.allAvailableModels.filter { CloudProviderRegistry.provider(for: $0.provider) != nil }
        case .custom:
            return transcriptionModelManager.allAvailableModels.filter { $0.provider == .custom }
        }
    }

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "bin")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.title = "Select a Whisper ggml .bin model"
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                await whisperModelManager.importWhisperModel(from: url)
            }
        }
    }

    // MARK: Enhancement — sections

    private var enhancementCard: some View {
        ZStack(alignment: .topTrailing) {
            SettingsCard(
                iconSystemName: "wand.and.stars",
                iconTint: Palette.accent,
                title: "Enhancement",
                subtitle: "Pass transcripts through an LLM before pasting.",
                statusText: enhancementService.enhanceLevel.displayName,
                statusTone: enhancementService.enhanceLevel == .none ? .neutral : .positive
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $enhancementService.enhanceLevel) {
                        ForEach(EnhanceLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(enhancementService.enhanceLevel.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    isEditingPrompt = false
                    selectedPromptForEdit = nil
                    activePanel = activePanel == .enhancementSettings ? nil : .enhancementSettings
                }
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(activePanel == .enhancementSettings ? Palette.accent : .secondary)
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
            .padding(.trailing, 14)
            .padding(.top, 14)
        }
    }

    private var aiProviderCard: some View {
        APIKeyManagementView()
            .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)
    }

    private var promptsCard: some View {
        ZStack(alignment: .topTrailing) {
            SettingsCard(
                iconSystemName: "text.bubble",
                iconTint: Palette.accent,
                title: "Enhancement Prompts",
                subtitle: "Pick the active style; reorder by drag.",
                statusText: "\(enhancementService.customPrompts.count)",
                statusTone: .neutral
            ) {
                ReorderablePromptGrid(
                    selectedPromptId: enhancementService.selectedPromptId,
                    onPromptSelected: { prompt in
                        enhancementService.setActivePrompt(prompt)
                    },
                    onEditPrompt: { prompt in
                        openPromptEditor(for: prompt)
                    },
                    onDeletePrompt: { prompt in
                        enhancementService.deletePrompt(prompt)
                    }
                )
                .padding(.vertical, 8)
            }

            Button {
                openPromptEditorForNew()
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
            .padding(.trailing, 14)
            .padding(.top, 14)
        }
        .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)
    }

    private func openPromptEditor(for prompt: CustomPrompt) {
        panelID = UUID()
        withAnimation(.smooth(duration: 0.3)) {
            isEditingPrompt = false
            selectedPromptForEdit = prompt
            activePanel = .promptEditor
        }
    }

    private func openPromptEditorForNew() {
        panelID = UUID()
        withAnimation(.smooth(duration: 0.3)) {
            selectedPromptForEdit = nil
            isEditingPrompt = true
            activePanel = .promptEditor
        }
    }
}

// MARK: - Reorderable Grid (file-private — moved from EnhancementSettingsView)
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

// MARK: - Drop Delegate (file-private — moved from EnhancementSettingsView)
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
