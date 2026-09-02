import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SwiftData

struct ModelsTab: View {
    // MARK: Environment / shared services

    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext

    @StateObject private var whisperPrompt = WhisperPrompt()
    @ObservedObject private var warmupCoordinator = WhisperModelWarmupCoordinator.shared

    @AppStorage("IsAcousticBoostingEnabled") private var isAcousticBoostingEnabled = false
    @State private var isPreparingAcousticModel = false
    @State private var acousticBoostingError: String?
    @State private var isRunningTranscriptionEval = false

    // Delete-confirmation alert for the per-tier transcription cards.
    @State private var isShowingDeleteAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var deleteActionClosure: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightedSection: ModelsTabSection?

    // MARK: - Introspectable composition descriptor
    //
    // The two flat sections of the Models tab are enumerated here. The body
    // renders `ForEach(renderedSections)` — and `renderedSections == allCases`
    // — through the EXHAUSTIVE `view(for:)` switch, so the rendered composition
    // IS this descriptor by construction: a section cannot be dropped from the
    // body without removing its enum case (a compile error in the exhaustive
    // switch). `SettingsModelsTabTests` asserts this equality.

    enum ModelsTabSection: CaseIterable, Hashable {
        case transcription
        case enhancement
    }

    /// The exact, ordered list the body's `ForEach` renders from. It IS
    /// `allCases`, so the rendered set equals the full descriptor.
    static var renderedSections: [ModelsTabSection] { ModelsTabSection.allCases }

    /// Flatness flags — the enhancement section is a single flat stack (level +
    /// on-device provider + prompts), NOT a provider accordion, and the tab
    /// does NOT segment the two surfaces behind a mode switch.
    /// `SettingsModelsTabTests` asserts both stay false.
    static let usesAccordion = false
    static let usesModeSwitch = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Self.renderedSections, id: \.self) { section in
                        view(for: section)
                            .id(section)
                            .settingsSectionHighlight(active: highlightedSection == section, reduceMotion: reduceMotion)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas)
            .alert(isPresented: $isShowingDeleteAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    primaryButton: .destructive(Text("Delete"), action: deleteActionClosure),
                    secondaryButton: .cancel()
                )
            }
            .tint(Brand.tint)
            .onReceive(NotificationCenter.default.publisher(for: .selectSettingsSection)) { note in
                handleSettingsSectionJump(note, thisTab: .models, sections: Self.renderedSections, label: { $0.searchLabel }, proxy: proxy, reduceMotion: reduceMotion, highlight: $highlightedSection)
            }
        }
    }

    // MARK: - Descriptor-driven rendering
    //
    // Exhaustive over ModelsTabSection: removing an enum case fails to compile,
    // so the descriptor cannot drift from what the body renders.

    @ViewBuilder
    private func view(for section: ModelsTabSection) -> some View {
        switch section {
        case .transcription:
            transcriptionSection
        case .enhancement:
            enhancementSection
        }
    }

    // MARK: - Transcription (quality tiers)

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                iconSystemName: "waveform",
                iconTint: Brand.tint,
                title: "Transcription",
                subtitle: "Pick a quality tier. Download, then select to use it."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(TranscriptionTier.allCases) { tier in
                        tierRow(for: tier)
                    }
                }
            }

            SettingsCard(
                iconSystemName: "testtube.2",
                iconTint: Brand.tint,
                title: "Experimental models",
                subtitle: "Additional local ASR candidates from the bundled registry."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(experimentalModels, id: \.name) { model in
                        experimentalModelRow(for: model)
                    }

                    if experimentalModels.isEmpty {
                        Text("No additional experimental models are available on this macOS version.")
                            .font(.system(size: 11))
                            .foregroundColor(Palette.inkSecondary)
                    }
                }
            }

            SettingsCard(
                iconSystemName: "waveform.badge.magnifyingglass",
                iconTint: Brand.tint,
                title: "Model sweep",
                subtitle: "Re-transcribe recent saved recordings through each usable local model."
            ) {
                Button {
                    runTranscriptionEval()
                } label: {
                    Label(isRunningTranscriptionEval ? "Running model sweep…" : "Run model sweep", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                .disabled(isRunningTranscriptionEval)
                .help("Writes transcription-eval-<stamp>.md using the shared transcription eval harness.")
            }

            SettingsCard(
                iconSystemName: "globe",
                iconTint: Brand.tint,
                title: "Language",
                subtitle: "Spoken language for the selected model."
            ) {
                LanguageSelectionView(
                    transcriptionModelManager: transcriptionModelManager,
                    displayMode: .full,
                    whisperPrompt: whisperPrompt
                )
            }

            SettingsCard(
                iconSystemName: "waveform.badge.mic",
                iconTint: Brand.tint,
                title: "Acoustic vocabulary boosting",
                subtitle: "Use the audio to confirm your custom-vocabulary spellings."
            ) {
                Toggle(isOn: $isAcousticBoostingEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Confirm custom terms against the audio")
                            .font(.system(size: 12, weight: .semibold))
                        HStack(spacing: 6) {
                            if isPreparingAcousticModel {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(acousticBoostingCaption)
                                .font(.system(size: 11))
                                .foregroundColor(acousticBoostingError == nil ? Palette.inkSecondary : Palette.stateFail)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .toggleStyle(.switch)
                .disabled(isPreparingAcousticModel)
                .onChange(of: isAcousticBoostingEnabled) { _, enabled in
                    guard enabled else { acousticBoostingError = nil; return }
                    prepareAcousticModel()
                }
            }
        }
    }

    private var experimentalModels: [any TranscriptionModel] {
        let tierModelIds = Set(TranscriptionTier.allCases.map { $0.modelId })
        return transcriptionModelManager.allAvailableModels.filter { model in
            guard !tierModelIds.contains(model.name) else { return false }
            if model.provider == .nativeApple {
                if #available(macOS 26, *) { return true }
                return false
            }
            return true
        }
    }

    private var acousticBoostingCaption: String {
        if let acousticBoostingError { return acousticBoostingError }
        if isPreparingAcousticModel { return "Downloading acoustic model…" }
        return "Downloads a ~110 MB model on enable. Realtime acoustic checks are logged only until the spotter is reliable."
    }

    private func prepareAcousticModel() {
        isPreparingAcousticModel = true
        acousticBoostingError = nil
        Task {
            do {
                try await AcousticVocabularyService.shared.prepareModel()
                await MainActor.run { isPreparingAcousticModel = false }
            } catch {
                await MainActor.run {
                    isPreparingAcousticModel = false
                    isAcousticBoostingEnabled = false
                    acousticBoostingError = "Couldn’t download the acoustic model. Turn the switch back on to retry."
                }
            }
        }
    }

    @ViewBuilder
    private func tierRow(for tier: TranscriptionTier) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(tier.title.uppercased())
                    .font(.microlabel(10.5))
                    .tracking(0.06 * 10.5)
                    .foregroundColor(Brand.tint)
                Text(tier.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.inkSecondary)
                Spacer(minLength: 0)
            }

            if let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == tier.modelId }) {
                modelCard(for: model)
            } else {
                Text("Model unavailable")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private func experimentalModelRow(for model: any TranscriptionModel) -> some View {
        if model.provider == .nativeApple {
            if #available(macOS 26, *) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Experimental Apple Speech path. This is useful as a native baseline, but docs currently flag it as experimental and it may not work yet.")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    modelCard(for: model)
                }
            }
        } else {
            modelCard(for: model)
        }
    }

    private func modelCard(for model: any TranscriptionModel) -> some View {
        let isWarming = (model as? WhisperModel).map { whisperModel in
            warmupCoordinator.isWarming(modelNamed: whisperModel.name)
        } ?? false

        return ModelCardView(
            model: model,
            fluidAudioModelManager: fluidAudioModelManager,
            transcriptionModelManager: transcriptionModelManager,
            isDownloaded: whisperModelManager.availableModels.contains { $0.name == model.name },
            isCurrent: transcriptionModelManager.currentTranscriptionModel?.name == model.name,
            downloadProgress: whisperModelManager.downloadProgress,
            downloadError: whisperModelManager.downloadErrors[model.name],
            modelURL: whisperModelManager.availableModels.first { $0.name == model.name }?.url,
            isWarming: isWarming,
            deleteAction: {
                if let downloadedModel = whisperModelManager.availableModels.first(where: { $0.name == model.name }) {
                    alertTitle = "Delete Model"
                    alertMessage = "Are you sure you want to delete the model '\(downloadedModel.name)'?"
                    deleteActionClosure = {
                        Task { await whisperModelManager.deleteModel(downloadedModel) }
                    }
                    isShowingDeleteAlert = true
                }
            },
            setDefaultAction: {
                transcriptionModelManager.setDefaultTranscriptionModel(model)
            },
            downloadAction: {
                if let whisperModel = model as? WhisperModel {
                    Task { await whisperModelManager.downloadModel(whisperModel) }
                }
            }
        )
    }

    private func runTranscriptionEval() {
        isRunningTranscriptionEval = true
        Task {
            defer { isRunningTranscriptionEval = false }
            do {
                let url = try await TranscriptionEvalHarness.run(
                    whisperModelManager: whisperModelManager,
                    fluidAudioModelManager: fluidAudioModelManager,
                    transcriptionModelManager: transcriptionModelManager,
                    modelContext: modelContext
                )
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NotificationManager.shared.showNotification(
                    title: "Transcription sweep failed: \(error.localizedDescription)",
                    type: .warning
                )
            }
        }
    }

    // MARK: - Enhancement (flat: level + on-device provider + prompts)

    private var enhancementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                iconSystemName: "wand.and.stars",
                iconTint: Brand.tint,
                title: "Enhancement",
                subtitle: "Clean transcripts on-device (Apple Foundation Models) before pasting.",
                statusText: enhancementService.isEnhancementEnabled ? "On" : "Off",
                statusTone: enhancementService.isEnhancementEnabled ? .positive : .neutral
            ) {
                Toggle(isOn: Binding(
                    get: { enhancementService.isEnhancementEnabled },
                    set: { enhancementService.isEnhancementEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clean up transcripts with AI")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Removes fillers and adds punctuation while preserving your wording. Off pastes the raw transcript.")
                            .font(.system(size: 11))
                            .foregroundColor(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }
}
