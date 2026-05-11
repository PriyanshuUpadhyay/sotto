import SwiftUI
import KeyboardShortcuts

// MARK: - ConfigurationView (P2.H / spec §3.12)
//
// Add/edit form for a Power Mode configuration. Rebuilt as a glass-card
// hero stack — five SettingsCard groupings (General, Trigger Scenarios,
// Transcription, AI Enhancement, Advanced) — replacing the v1 Form layout.
//
// Layering (per spec §3.3): the panel host already paints a window-background;
// each SettingsCard wraps its content in a translucent GlassCard so the form
// reads as a vertical stack of glass islands rather than a grouped Form.
//
// All v1 functionality preserved (reviewer focus):
//   • emoji picker popover, name field, app picker popover, website list
//   • transcription model + language pickers (auto-detection rules intact)
//   • AI provider/model/prompt/context-awareness pickers
//   • set-as-default toggle, auto-send key picker, KeyboardShortcuts.Recorder
//   • validation alert + delete confirmation + save flow

struct ConfigurationView: View {
    let mode: ConfigurationMode
    let powerModeManager: PowerModeManager
    var onDismiss: () -> Void
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @FocusState private var isNameFieldFocused: Bool

    @State private var configName: String = "New Power Mode"
    @State private var selectedEmoji: String = "💼"
    @State private var isShowingEmojiPicker = false
    @State private var isShowingAppPicker = false
    @State private var enhanceLevel: EnhanceLevel
    @State private var selectedPromptId: UUID?
    @State private var selectedTranscriptionModelName: String?
    @State private var selectedLanguage: String?
    @State private var installedApps: [(url: URL, name: String, bundleId: String, icon: NSImage)] = []
    @State private var searchText = ""
    @State private var validationErrors: [PowerModeValidationError] = []
    @State private var showValidationAlert = false
    @State private var selectedAIProvider: String?
    @State private var selectedAIModel: String?
    @State private var selectedAppConfigs: [AppConfig] = []
    @State private var websiteConfigs: [URLConfig] = []
    @State private var newWebsiteURL: String = ""
    @State private var useScreenCapture = false
    @State private var useClipboardContext = false
    @State private var autoSendKey: AutoSendKey = .none
    @State private var isDefault = false
    @State private var isShowingDeleteConfirmation = false
    @State private var powerModeConfigId: UUID = UUID()

    private var effectiveModelName: String? {
        selectedTranscriptionModelName ?? transcriptionModelManager.currentTranscriptionModel?.name
    }

    private var filteredApps: [(url: URL, name: String, bundleId: String, icon: NSImage)] {
        if searchText.isEmpty { return installedApps }
        return installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var canSave: Bool { !configName.isEmpty }

    private func languageSelectionDisabled() -> Bool {
        guard let selectedModelName = effectiveModelName,
              let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == selectedModelName })
        else { return false }
        return model.provider == .fluidAudio || model.provider == .gemini
    }

    init(mode: ConfigurationMode, powerModeManager: PowerModeManager, onDismiss: @escaping () -> Void) {
        self.mode = mode
        self.powerModeManager = powerModeManager
        self.onDismiss = onDismiss

        switch mode {
        case .add:
            let newId = UUID()
            _powerModeConfigId = State(initialValue: newId)
            _enhanceLevel = State(initialValue: .default)
            _selectedPromptId = State(initialValue: nil)
            _selectedTranscriptionModelName = State(initialValue: nil)
            _selectedLanguage = State(initialValue: nil)
            _configName = State(initialValue: "")
            _selectedEmoji = State(initialValue: "✏️")
            _useScreenCapture = State(initialValue: false)
            _useClipboardContext = State(initialValue: false)
            _autoSendKey = State(initialValue: .none)
            _isDefault = State(initialValue: false)
            // Use UserDefaults directly since EnvironmentObjects aren't available in init
            _selectedAIProvider = State(initialValue: UserDefaults.standard.string(forKey: "selectedAIProvider"))
            _selectedAIModel = State(initialValue: nil)
        case .edit(let config):
            // Fetch latest version in case config was modified elsewhere
            let latestConfig = powerModeManager.getConfiguration(with: config.id) ?? config
            _powerModeConfigId = State(initialValue: latestConfig.id)
            _enhanceLevel = State(initialValue: latestConfig.enhanceLevel)
            _selectedPromptId = State(initialValue: latestConfig.selectedPrompt.flatMap { UUID(uuidString: $0) })
            _selectedTranscriptionModelName = State(initialValue: latestConfig.selectedTranscriptionModelName)
            _selectedLanguage = State(initialValue: latestConfig.selectedLanguage)
            _configName = State(initialValue: latestConfig.name)
            _selectedEmoji = State(initialValue: latestConfig.emoji)
            _selectedAppConfigs = State(initialValue: latestConfig.appConfigs ?? [])
            _websiteConfigs = State(initialValue: latestConfig.urlConfigs ?? [])
            _useScreenCapture = State(initialValue: latestConfig.useScreenCapture)
            _useClipboardContext = State(initialValue: latestConfig.useClipboardContext)
            _autoSendKey = State(initialValue: latestConfig.autoSendKey)
            _isDefault = State(initialValue: latestConfig.isDefault)
            _selectedAIProvider = State(initialValue: latestConfig.selectedAIProvider)
            _selectedAIModel = State(initialValue: latestConfig.selectedAIModel)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            scrollBody
            footer
        }
        .powerModeValidationAlert(errors: validationErrors, isPresented: $showValidationAlert)
        .confirmationDialog(
            "Delete Power Mode?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if case .edit(let config) = mode {
                Button("Delete", role: .destructive) {
                    powerModeManager.removeConfiguration(with: config.id)
                    onDismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if case .edit(let config) = mode {
                Text("Are you sure you want to delete the '\(config.name)' power mode? This action cannot be undone.")
            }
        }
        .onAppear {
            if case .add = mode {
                if selectedAIProvider == nil {
                    selectedAIProvider = aiService.selectedProvider.rawValue
                }
                if selectedAIModel == nil || selectedAIModel?.isEmpty == true {
                    selectedAIModel = aiService.currentModel
                }
            }

            if enhanceLevel != .none && selectedPromptId == nil {
                selectedPromptId = enhancementService.allPrompts.first?.id
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFieldFocused = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(mode.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Button(action: onDismiss) {
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
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if case .edit = mode {
                Button("Delete", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .buttonStyle(.bordered)
            } else {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                saveConfiguration()
            } label: {
                Text("Save Changes")
                    .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(Divider().opacity(0.5), alignment: .top)
    }

    // MARK: - Scrollable glass body

    private var scrollBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                generalCard
                triggerScenariosCard
                transcriptionCard
                aiEnhancementCard
                advancedCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - General

    private var generalCard: some View {
        SettingsCard(
            iconSystemName: "sparkles",
            iconTint: Palette.warn,
            title: "General",
            subtitle: "Pick an emoji and name this Power Mode."
        ) {
            HStack(spacing: 12) {
                emojiButton
                TextField("Name", text: $configName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)
            }
        }
    }

    private var emojiButton: some View {
        Button {
            isShowingEmojiPicker.toggle()
        } label: {
            Text(selectedEmoji)
                .font(.system(size: 24))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Palette.warn.opacity(0.32), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingEmojiPicker, arrowEdge: .bottom) {
            EmojiPickerView(
                selectedEmoji: $selectedEmoji,
                isPresented: $isShowingEmojiPicker
            )
        }
    }

    // MARK: - Trigger Scenarios

    private var triggerScenariosCard: some View {
        SettingsCard(
            iconSystemName: "scope",
            iconTint: Palette.accent,
            title: "Trigger Scenarios",
            subtitle: "Match the active app or website."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                applicationsBlock
                Divider().opacity(0.3)
                websitesBlock
            }
        }
    }

    private var applicationsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Applications")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                AddIconButton(helpText: "Add application") {
                    loadInstalledApps()
                    isShowingAppPicker = true
                }
                .popover(isPresented: $isShowingAppPicker, arrowEdge: .bottom) {
                    AppPickerPopover(
                        installedApps: filteredApps,
                        selectedAppConfigs: $selectedAppConfigs,
                        searchText: $searchText
                    )
                }
            }

            if selectedAppConfigs.isEmpty {
                Text("No applications added")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 44, maximum: 50), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(selectedAppConfigs) { appConfig in
                        appIconCell(for: appConfig)
                    }
                }
            }
        }
    }

    private func appIconCell(for appConfig: AppConfig) -> some View {
        ZStack(alignment: .topTrailing) {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appConfig.bundleIdentifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 0.078, green: 0.078, blue: 0.110).opacity(0.55))
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
            }

            Button {
                selectedAppConfigs.removeAll(where: { $0.id == appConfig.id })
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }

    private var websitesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Websites")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)

            HStack {
                TextField("example.com", text: $newWebsiteURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { addWebsite() }

                AddIconButton(helpText: "Add website", isDisabled: newWebsiteURL.isEmpty) {
                    addWebsite()
                }
            }

            if websiteConfigs.isEmpty {
                Text("No websites added")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(websiteConfigs) { urlConfig in
                        websiteCell(for: urlConfig)
                    }
                }
            }
        }
    }

    private func websiteCell(for urlConfig: URLConfig) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            Text(urlConfig.url)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                websiteConfigs.removeAll(where: { $0.id == urlConfig.id })
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Palette.hairlineSoft, lineWidth: 0.5)
        )
    }

    // MARK: - Transcription

    private var transcriptionCard: some View {
        SettingsCard(
            iconSystemName: "waveform",
            iconTint: Palette.accent,
            title: "Transcription",
            subtitle: "Pick the model and language for this Power Mode."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                transcriptionModelPicker
                transcriptionLanguagePicker
            }
        }
    }

    @ViewBuilder
    private var transcriptionModelPicker: some View {
        if transcriptionModelManager.usableModels.isEmpty {
            Text("No transcription models available. Connect to a cloud service or download a local model in the AI Models tab.")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
        } else {
            let modelBinding = Binding<String?>(
                get: { selectedTranscriptionModelName ?? transcriptionModelManager.currentTranscriptionModel?.name },
                set: { selectedTranscriptionModelName = $0 }
            )

            Picker("Model", selection: modelBinding) {
                ForEach(transcriptionModelManager.usableModels, id: \.name) { model in
                    Text(model.displayName).tag(model.name as String?)
                }
            }
            .onChange(of: selectedTranscriptionModelName) { _, newModelName in
                // Auto-set language to "auto" for models that only support auto-detection
                if let modelName = newModelName ?? transcriptionModelManager.currentTranscriptionModel?.name,
                   let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == modelName }),
                   model.provider == .fluidAudio || model.provider == .gemini {
                    selectedLanguage = "auto"
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptionLanguagePicker: some View {
        if languageSelectionDisabled() {
            LabeledContent("Language") {
                Text("Autodetected")
                    .foregroundColor(.secondary)
            }
            .onAppear {
                selectedLanguage = "auto"
            }
        } else if let selectedModel = effectiveModelName,
                  let modelInfo = transcriptionModelManager.allAvailableModels.first(where: { $0.name == selectedModel }),
                  modelInfo.isMultilingualModel {
            let languageBinding = Binding<String?>(
                get: { selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto" },
                set: { selectedLanguage = $0 }
            )

            Picker("Language", selection: languageBinding) {
                ForEach(modelInfo.supportedLanguages.sorted(by: {
                    if $0.key == "auto" { return true }
                    if $1.key == "auto" { return false }
                    return $0.value < $1.value
                }), id: \.key) { key, value in
                    Text(value).tag(key as String?)
                }
            }
        } else if let selectedModel = effectiveModelName,
                  let modelInfo = transcriptionModelManager.allAvailableModels.first(where: { $0.name == selectedModel }),
                  !modelInfo.isMultilingualModel {
            EmptyView()
                .onAppear {
                    if selectedLanguage == nil {
                        selectedLanguage = "en"
                    }
                }
        }
    }

    // MARK: - AI Enhancement

    private var aiEnhancementCard: some View {
        SettingsCard(
            iconSystemName: "sparkles",
            iconTint: Palette.accent,
            title: "AI Enhancement",
            subtitle: "Reshape transcripts with the model of your choice."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cleanup Level")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    Picker("", selection: $enhanceLevel) {
                        ForEach(EnhanceLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: enhanceLevel) { _, newValue in
                        // Mirror the legacy onChange — when the user dials AWAY from .none,
                        // seed defaults so the rest of the card has something to render.
                        if newValue != .none {
                            if selectedAIProvider == nil {
                                selectedAIProvider = aiService.selectedProvider.rawValue
                            }
                            if selectedAIModel == nil {
                                selectedAIModel = aiService.currentModel
                            }
                            if selectedPromptId == nil {
                                selectedPromptId = enhancementService.allPrompts.first?.id
                            }
                        }
                    }
                    Text(enhanceLevel.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if enhanceLevel != .none {
                    aiProviderPicker
                    aiModelPicker
                    enhancementPromptPicker
                    Toggle("Context Awareness", isOn: $useScreenCapture)
                        .toggleStyle(SwitchToggleStyle(tint: Palette.accent))
                    Toggle("Use Clipboard Context", isOn: $useClipboardContext)
                        .toggleStyle(SwitchToggleStyle(tint: Palette.accent))
                }
            }
        }
    }

    private var providerBinding: Binding<AIProvider> {
        Binding<AIProvider>(
            get: {
                if let providerName = selectedAIProvider,
                   let provider = AIProvider(rawValue: providerName) {
                    return provider
                }
                return aiService.selectedProvider
            },
            set: { newValue in
                selectedAIProvider = newValue.rawValue
                selectedAIModel = nil
            }
        )
    }

    @ViewBuilder
    private var aiProviderPicker: some View {
        if aiService.connectedProviders.isEmpty {
            LabeledContent("AI Provider") {
                Text("No providers connected")
                    .foregroundColor(.secondary)
                    .italic()
            }
        } else {
            Picker("AI Provider", selection: providerBinding) {
                ForEach(aiService.connectedProviders.filter { $0 != .elevenLabs && $0 != .deepgram }, id: \.self) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .onChange(of: selectedAIProvider) { _, newValue in
                if let provider = newValue.flatMap({ AIProvider(rawValue: $0) }) {
                    selectedAIModel = provider.defaultModel
                }
            }
        }
    }

    @ViewBuilder
    private var aiModelPicker: some View {
        let providerName = selectedAIProvider ?? aiService.selectedProvider.rawValue
        if let provider = AIProvider(rawValue: providerName), provider != .custom {
            let models = aiService.availableModels(for: provider)
            if models.isEmpty {
                LabeledContent("AI Model") {
                    Text(provider == .openRouter ? "No models loaded" : "No models available")
                        .foregroundColor(.secondary)
                        .italic()
                }
            } else {
                let modelBinding = Binding<String>(
                    get: {
                        if let model = selectedAIModel, !model.isEmpty { return model }
                        return aiService.currentModel
                    },
                    set: { newModelValue in
                        selectedAIModel = newModelValue
                    }
                )

                Picker("AI Model", selection: modelBinding) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                if provider == .openRouter {
                    Button("Refresh Models") {
                        Task { await aiService.fetchOpenRouterModels() }
                    }
                    .help("Refresh models")
                }
            }
        }
    }

    @ViewBuilder
    private var enhancementPromptPicker: some View {
        if enhancementService.allPrompts.isEmpty {
            LabeledContent("Enhancement Prompt") {
                Text("No prompts available")
                    .foregroundColor(.secondary)
            }
        } else {
            Picker("Enhancement Prompt", selection: $selectedPromptId) {
                ForEach(enhancementService.allPrompts) { prompt in
                    Text(prompt.title).tag(prompt.id as UUID?)
                }
            }
        }
    }

    // MARK: - Advanced

    private var advancedCard: some View {
        SettingsCard(
            iconSystemName: "gearshape.fill",
            iconTint: Palette.neutral,
            title: "Advanced",
            subtitle: "Default behavior, auto-send, keyboard shortcut."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $isDefault) {
                    HStack(spacing: 6) {
                        Text("Set as default")
                        InfoTip("Default power mode is used when no specific app or website matches are found.")
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: Palette.warn))

                Picker(selection: $autoSendKey) {
                    ForEach(AutoSendKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Auto Send")
                        InfoTip("Automatically presses a key combination after pasting text. Useful for chat applications or forms that use different send shortcuts.")
                    }
                }

                HStack {
                    Text("Keyboard Shortcut")
                    InfoTip("Assign a unique keyboard shortcut to instantly activate this Power Mode and start recording.")

                    Spacer()

                    KeyboardShortcuts.Recorder(for: .powerMode(id: powerModeConfigId))
                        .controlSize(.regular)
                        .frame(minHeight: 28)
                }
            }
        }
    }

    // MARK: - Actions

    private func addWebsite() {
        guard !newWebsiteURL.isEmpty else { return }
        let cleanedURL = powerModeManager.cleanURL(newWebsiteURL)
        websiteConfigs.append(URLConfig(url: cleanedURL))
        newWebsiteURL = ""
    }

    private func getConfigForForm() -> PowerModeConfig {
        let shortcut = KeyboardShortcuts.getShortcut(for: .powerMode(id: powerModeConfigId))
        let hotkeyString = shortcut != nil ? "configured" : nil

        switch mode {
        case .add:
            return PowerModeConfig(
                id: powerModeConfigId,
                name: configName,
                emoji: selectedEmoji,
                appConfigs: selectedAppConfigs.isEmpty ? nil : selectedAppConfigs,
                urlConfigs: websiteConfigs.isEmpty ? nil : websiteConfigs,
                enhanceLevel: enhanceLevel,
                selectedPrompt: selectedPromptId?.uuidString,
                selectedTranscriptionModelName: selectedTranscriptionModelName,
                selectedLanguage: selectedLanguage,
                useScreenCapture: useScreenCapture,
                useClipboardContext: useClipboardContext,
                selectedAIProvider: selectedAIProvider,
                selectedAIModel: selectedAIModel,
                autoSendKey: autoSendKey,
                isDefault: isDefault,
                hotkeyShortcut: hotkeyString
            )
        case .edit(let config):
            var updatedConfig = config
            updatedConfig.name = configName
            updatedConfig.emoji = selectedEmoji
            updatedConfig.enhanceLevel = enhanceLevel
            updatedConfig.selectedPrompt = selectedPromptId?.uuidString
            updatedConfig.selectedTranscriptionModelName = selectedTranscriptionModelName
            updatedConfig.selectedLanguage = selectedLanguage
            updatedConfig.appConfigs = selectedAppConfigs.isEmpty ? nil : selectedAppConfigs
            updatedConfig.urlConfigs = websiteConfigs.isEmpty ? nil : websiteConfigs
            updatedConfig.useScreenCapture = useScreenCapture
            updatedConfig.useClipboardContext = useClipboardContext
            updatedConfig.autoSendKey = autoSendKey
            updatedConfig.selectedAIProvider = selectedAIProvider
            updatedConfig.selectedAIModel = selectedAIModel
            updatedConfig.isDefault = isDefault
            updatedConfig.hotkeyShortcut = hotkeyString
            return updatedConfig
        }
    }

    private func loadInstalledApps() {
        let userAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
        let localAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
        let systemAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .systemDomainMask)
        let allAppURLs = userAppURLs + localAppURLs + systemAppURLs

        var allApps: [URL] = []

        func scanDirectory(_ baseURL: URL, depth: Int = 0) {
            // Prevent infinite recursion from circular symlinks
            guard depth < 5 else { return }
            guard let enumerator = FileManager.default.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for item in enumerator {
                guard let url = item as? URL else { continue }
                let resolvedURL = url.resolvingSymlinksInPath()

                if resolvedURL.pathExtension == "app" {
                    allApps.append(resolvedURL)
                    enumerator.skipDescendants()
                    continue
                }

                // Traverse symlinked directories manually
                var isDirectory: ObjCBool = false
                if url != resolvedURL &&
                   FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) &&
                   isDirectory.boolValue {
                    enumerator.skipDescendants()
                    scanDirectory(resolvedURL, depth: depth + 1)
                }
            }
        }

        for baseURL in allAppURLs {
            scanDirectory(baseURL)
        }

        installedApps = allApps.compactMap { url in
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier,
                  let name = (bundle.infoDictionary?["CFBundleName"] as? String) ??
                            (bundle.infoDictionary?["CFBundleDisplayName"] as? String) else {
                return nil
            }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (url: url, name: name, bundleId: bundleId, icon: icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func saveConfiguration() {
        let config = getConfigForForm()
        let validator = PowerModeValidator(powerModeManager: powerModeManager)
        validationErrors = validator.validateForSave(config: config, mode: mode)

        if !validationErrors.isEmpty {
            showValidationAlert = true
            return
        }

        if isDefault {
            powerModeManager.setAsDefault(configId: config.id, skipSave: true)
        }

        switch mode {
        case .add:
            powerModeManager.addConfiguration(config)
        case .edit:
            powerModeManager.updateConfiguration(config)
        }

        onDismiss()
    }
}
