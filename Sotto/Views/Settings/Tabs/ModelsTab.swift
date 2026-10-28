import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SwiftData

struct ModelsTab: View {
    // MARK: Environment / shared services

    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext

    @StateObject private var whisperPrompt = WhisperPrompt()
    @ObservedObject private var warmupCoordinator = WhisperModelWarmupCoordinator.shared

    @AppStorage("IsAcousticBoostingEnabled") private var isAcousticBoostingEnabled = false
    @State private var isPreparingAcousticModel = false
    @State private var acousticBoostingError: String?
    @State private var isRunningTranscriptionEval = false
    @State private var modelSearchText = ""
    @AppStorage("EnhancementProvider") var enhancementProvider = AIProvider.foundationModels.rawValue
    @AppStorage(ConciseCleanup.userDefaultsKey) var isConciseEnhancementEnabled = false
    @AppStorage("EnhancementGGUFModelSlug") var enhancementGGUFModelSlug = GGUFModelRegistry.curated.first?.slug ?? "s1-mini"
    @ObservedObject var ggufDownloadManager = GGUFDownloadManager.shared
    @State var downloadedGGUFSlugs: Set<String> = []

    // Delete-confirmation / error alert for model cards.
    @State var isShowingDeleteAlert = false
    @State var isDeleteConfirmation = false
    @State var alertTitle = ""
    @State var alertMessage = ""
    @State var deleteActionClosure: () -> Void = {}

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
                if isDeleteConfirmation {
                    Alert(
                        title: Text(alertTitle),
                        message: Text(alertMessage),
                        primaryButton: .destructive(Text("Delete"), action: deleteActionClosure),
                        secondaryButton: .cancel()
                    )
                } else {
                    Alert(
                        title: Text(alertTitle),
                        message: Text(alertMessage),
                        dismissButton: .default(Text("OK"))
                    )
                }
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
    func view(for section: ModelsTabSection) -> some View {
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
                subtitle: "Search by model or language. Download a model, then select it to use it."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Search models or languages", text: $modelSearchText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Search transcription models")

                    ForEach(matchingModels, id: \.name) { model in
                        if let tier = TranscriptionTier(modelId: model.name) {
                            tierRow(for: tier, model: model)
                        } else {
                            modelCard(for: model)
                        }
                    }

                    if matchingModels.isEmpty {
                        Text("No models match. Try another name or language.")
                            .font(.ui(11))
                            .foregroundColor(Palette.inkSecondary)
                        Button("Clear search") {
                            modelSearchText = ""
                        }
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
                            .font(.ui(12, weight: .semibold))
                        HStack(spacing: 6) {
                            if isPreparingAcousticModel {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(acousticBoostingCaption)
                                .font(.ui(11))
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

    private var catalogModels: [any TranscriptionModel] {
        let models = transcriptionModelManager.allAvailableModels.filter { model in
            if model.provider == .nativeApple {
                if #available(macOS 26, *) { return true }
                return false
            }
            return true
        }
        let tiers = TranscriptionTier.allCases.compactMap { tier in
            models.first { $0.name == tier.modelId }
        }
        return tiers + models.filter { TranscriptionTier(modelId: $0.name) == nil }
    }

    private var matchingModels: [any TranscriptionModel] {
        TranscriptionModelSearch.results(
            in: catalogModels, query: modelSearchText
        )
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

    private func tierRow(for tier: TranscriptionTier, model: any TranscriptionModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(tier.title.uppercased())
                    .font(.microlabel(10.5))
                    .tracking(0.06 * 10.5)
                    .foregroundColor(Brand.tint)
                Text(tier.subtitle)
                    .font(.ui(11))
                    .foregroundColor(Palette.inkSecondary)
                Spacer(minLength: 0)
            }

            modelCard(for: model)
        }
    }

    private func modelCard(for model: any TranscriptionModel) -> some View {
        let isWarming = (model as? WhisperModel).map { whisperModel in
            warmupCoordinator.isWarming(modelNamed: whisperModel.name)
        } ?? false
        let whisperModel = model as? WhisperModel
        let isPaused = whisperModel.map { whisperModelManager.isPaused($0) } ?? false

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
            isPaused: isPaused,
            deleteAction: {
                if let downloadedModel = whisperModelManager.availableModels.first(where: { $0.name == model.name }) {
                    alertTitle = "Delete Model"
                    alertMessage = "Are you sure you want to delete the model '\(downloadedModel.name)'?"
                    deleteActionClosure = {
                        Task { await whisperModelManager.deleteModel(downloadedModel) }
                    }
                    isDeleteConfirmation = true
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
            },
            pauseAction: {
                if let whisperModel = model as? WhisperModel {
                    whisperModelManager.pauseDownload(whisperModel)
                }
            },
            resumeAction: {
                if let whisperModel = model as? WhisperModel {
                    whisperModelManager.resumeDownload(whisperModel)
                }
            },
            cancelAction: {
                if let whisperModel = model as? WhisperModel {
                    whisperModelManager.cancelDownload(whisperModel)
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
}
