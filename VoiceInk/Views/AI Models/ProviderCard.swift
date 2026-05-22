import SwiftUI
import LLMkit

// MARK: - ProviderCard
//
// Gallery cell for the AI Models tab — provider tile + name + status dot +
// model count + chevron, expandable to reveal API-key entry, available models,
// and Test Connection.
//
// Architecture:
//   - One card per `AIProvider` (gallery filters speech-only providers).
//   - Parent owns `expandedProvider: AIProvider?` and toggles it on tap.
//   - Expanding a card also calls `onActivate` → sets `aiService.selectedProvider`
//     so existing `saveAPIKey` / `verifyAPIKey` (keyed off selectedProvider)
//     work without an AIService refactor.
//   - Per-provider expanded UI (key field, ollama URL, custom endpoint, MLX
//     picker, local CLI editor, foundation models status) lives in this file
//     so the gallery cell knows how to render itself for any provider type.
//
// Visuals reuse `HaloMaterial(phase: .hidden)` per spec §2.3 + §3.7. Provider
// tint comes from `ProviderChipStyle` (extracted helper) and is applied to the
// tile fill, status dot border, and active-card stroke.

struct ProviderCard: View {
    let provider: AIProvider
    @Binding var expandedProvider: AIProvider?
    /// Called when the card expands — flips `aiService.selectedProvider` to
    /// `provider` so save/verify operations target this provider.
    var onActivate: () -> Void

    @EnvironmentObject private var aiService: AIService
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared

    // Per-card local state
    @State private var pendingKey: String = ""
    @State private var verifyState: VerifyState = .idle
    @State private var verifyMessage: String? = nil
    @State private var hovering = false

    // Ollama-specific local state
    @State private var ollamaBaseURL: String = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
    @State private var ollamaModels: [OllamaModel] = []
    @State private var selectedOllamaModel: String = UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
    @State private var isCheckingOllama = false
    @State private var isEditingOllamaURL = false

    // Local CLI-specific local state
    @State private var localCLICommandTemplate: String = ""
    @State private var localCLITimeoutSeconds: Double = LocalCLIService.defaultTimeoutSeconds
    @State private var isSyncingLocalCLIState = false

    enum VerifyState {
        case idle, verifying, success, failure
    }

    private var isExpanded: Bool { expandedProvider == provider }
    private var isActive: Bool { aiService.selectedProvider == provider }
    private var tint: Color { ProviderChipStyle.tint(for: provider) }
    private var symbol: String { ProviderChipStyle.symbol(for: provider) }
    private var displayName: String { ProviderChipStyle.displayName(for: provider) }

    private var isConnected: Bool {
        switch provider {
        case .ollama:
            return !ollamaModels.isEmpty
        case .localCLI:
            // Read off the active service via aiService.isAPIKeyValid only when
            // this provider is the selected one; otherwise check stored template.
            return isActive ? aiService.isAPIKeyValid : !aiService.localCLICommandTemplate.isEmpty
        case .foundationModels:
            if #available(macOS 26.0, *) {
                return AFMProvider.isAvailable
            }
            return false
        case .mlx:
            let modelId = UserDefaults.standard.string(forKey: "mlx_selected_model_id") ?? ""
            return !modelId.isEmpty && MLXModelDownloader.status(for: modelId) == .downloaded
        default:
            return APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue)
        }
    }

    private var statusText: String {
        switch provider {
        case .ollama:
            if isCheckingOllama { return "Checking…" }
            return ollamaModels.isEmpty ? "Disconnected" : "Connected"
        case .foundationModels:
            if #available(macOS 26.0, *) {
                return AFMProvider.isAvailable ? "Available" : "Unavailable"
            }
            return "macOS 26+"
        case .mlx:
            return isConnected ? "Model ready" : "No model"
        case .localCLI:
            return isConnected ? "Configured" : "No command"
        default:
            return isConnected ? "Connected" : "No key"
        }
    }

    private var modelCount: Int {
        aiService.availableModels(for: provider).count
    }

    private var modelCountText: String {
        switch provider {
        case .foundationModels: return "On-device"
        case .custom: return "Custom endpoint"
        case .mlx: return "Local MLX"
        case .localCLI: return "Local CLI"
        case .ollama:
            return ollamaModels.isEmpty ? "No models loaded" : "\(ollamaModels.count) models"
        case .openRouter:
            let n = modelCount
            return n == 0 ? "Refresh to load" : "\(n) models"
        default:
            let n = modelCount
            return n == 0 ? "—" : "\(n) models"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(14)
                .contentShape(Rectangle())
                .onTapGesture { toggleExpand() }

            if isExpanded {
                Divider()
                    .background(Palette.hairlineSoft)
                    .padding(.horizontal, 14)
                expanded
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            HaloMaterial(shape: shape, phase: .hidden)
        )
        .overlay(
            shape.stroke(
                isActive ? Palette.brandAcid.opacity(0.55) : Palette.hairline,
                lineWidth: isActive ? 1.5 : 1
            )
        )
        .clipShape(shape)
        .animation(motion.reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: isExpanded)
        .onHover { hovering = $0 }
        .onAppear { onCardAppear() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            // Provider tile — same language as ProviderChip but at 36pt scale.
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.brandAcid.opacity(0.18))
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Palette.brandAcid.opacity(0.36), lineWidth: 0.5)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Palette.brandAcid)
            }
            .frame(width: 36, height: 36)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(isConnected ? Palette.success : Palette.neutral)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5)
                    )
                    .offset(x: 3, y: -3)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .tracking(0.06 * 9.5)
                            .foregroundColor(Palette.brandAcid)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(Palette.brandAcid.opacity(0.16)))
                            .overlay(Capsule().stroke(Palette.brandAcid.opacity(0.42), lineWidth: 0.5))
                    }
                }

                Text(modelCountText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                StatusPill(text: statusText, tone: isConnected ? .positive : .neutral)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
    }

    // MARK: - Expanded body — routes by provider type

    @ViewBuilder
    private var expanded: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch provider {
            case .ollama:
                ollamaExpanded
            case .localCLI:
                localCLIExpanded
            case .foundationModels:
                foundationModelsExpanded
            case .mlx:
                MLXModelPickerView()
                if !aiService.isAPIKeyValid {
                    Text("Pick a downloaded model above to enable MLX enhancement.")
                        .font(.caption)
                        .foregroundColor(Palette.warn)
                }
            case .custom:
                customExpanded
            case .openRouter:
                openRouterExpanded
                keyEntrySection
                testConnectionSection
            default:
                modelPickerSection
                keyEntrySection
                testConnectionSection
            }
        }
    }

    // MARK: - Standard key-based providers

    @ViewBuilder
    private var modelPickerSection: some View {
        if !aiService.availableModels.isEmpty {
            Picker("Model", selection: Binding(
                get: { aiService.currentModel },
                set: { aiService.selectModel($0) }
            )) {
                ForEach(aiService.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        }
    }

    @ViewBuilder
    private var keyEntrySection: some View {
        if aiService.isAPIKeyValid {
            HStack {
                Text("API Key")
                    .font(.system(size: 12))
                Spacer()
                Text("••••••••")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                Button("Remove", role: .destructive) {
                    aiService.clearAPIKey()
                    pendingKey = ""
                    verifyState = .idle
                    verifyMessage = nil
                }
                .controlSize(.small)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                SecureField("API Key", text: $pendingKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if let url = apiKeyURL {
                        Link(destination: url) {
                            HStack(spacing: 5) {
                                Image(systemName: "key.fill")
                                Text("Get API Key")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(tint)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 9)
                            .background(Capsule().fill(tint.opacity(0.14)))
                            .overlay(Capsule().stroke(tint.opacity(0.32), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button(action: saveAndVerify) {
                        HStack(spacing: 4) {
                            if verifyState == .verifying {
                                ProgressView().controlSize(.small)
                            }
                            Text("Verify and Save")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .disabled(pendingKey.isEmpty || verifyState == .verifying)
                }
            }
        }

        verifyResultLabel
    }

    @ViewBuilder
    private var verifyResultLabel: some View {
        if verifyState == .failure, let msg = verifyMessage {
            Text(msg)
                .font(.caption)
                .foregroundColor(Palette.brandAcid)
                .fixedSize(horizontal: false, vertical: true)
        } else if verifyState == .success {
            Text("API key verified.")
                .font(.caption)
                .foregroundColor(Palette.success)
        }
    }

    @ViewBuilder
    private var testConnectionSection: some View {
        if aiService.isAPIKeyValid {
            HStack {
                Spacer()
                Button(action: testConnection) {
                    HStack(spacing: 4) {
                        if verifyState == .verifying {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text("Test Connection")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .controlSize(.small)
                .disabled(verifyState == .verifying)
            }
        }
    }

    // MARK: - Ollama

    @ViewBuilder
    private var ollamaExpanded: some View {
        if isEditingOllamaURL {
            HStack {
                TextField("Base URL", text: $ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    aiService.updateOllamaBaseURL(ollamaBaseURL)
                    isEditingOllamaURL = false
                    refreshOllama()
                }
                .controlSize(.small)
            }
        } else {
            HStack {
                Text("Server: \(ollamaBaseURL)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Edit") { isEditingOllamaURL = true }
                    .controlSize(.small)
                Button(action: {
                    ollamaBaseURL = "http://localhost:11434"
                    aiService.updateOllamaBaseURL(ollamaBaseURL)
                    refreshOllama()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .controlSize(.small)
                .help("Reset to default")
            }
        }

        if !ollamaModels.isEmpty {
            Picker("Model", selection: $selectedOllamaModel) {
                ForEach(ollamaModels) { model in
                    Text(model.name).tag(model.name)
                }
            }
            .onChange(of: selectedOllamaModel) { _, newValue in
                aiService.updateSelectedOllamaModel(newValue)
            }
        }

        HStack {
            Spacer()
            Button(action: refreshOllama) {
                HStack(spacing: 4) {
                    if isCheckingOllama {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isCheckingOllama ? "Checking…" : "Test Connection")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .controlSize(.small)
            .disabled(isCheckingOllama)
        }

        if let msg = verifyMessage, verifyState == .failure {
            Text(msg)
                .font(.caption)
                .foregroundColor(Palette.brandAcid)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Local CLI

    @ViewBuilder
    private var localCLIExpanded: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Command")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Menu("Load Template") {
                    ForEach(LocalCLITemplate.allCases) { template in
                        Button(template.displayName) {
                            aiService.loadLocalCLITemplate(template)
                            syncLocalCLIStateFromService()
                        }
                    }
                }
                .controlSize(.small)
            }

            TextEditor(text: $localCLICommandTemplate)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.leading)
                .frame(minHeight: 100)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .onChange(of: localCLICommandTemplate) { _, newValue in
                    guard !isSyncingLocalCLIState else { return }
                    if newValue != aiService.localCLICommandTemplate {
                        aiService.updateLocalCLICommandTemplate(newValue)
                    }
                }
        }

        Picker("Timeout", selection: $localCLITimeoutSeconds) {
            ForEach([15.0, 30.0, 45.0, 60.0, 90.0, 120.0, 180.0, 300.0], id: \.self) { secs in
                Text("\(Int(secs))s").tag(secs)
            }
        }
        .onChange(of: localCLITimeoutSeconds) { _, newValue in
            aiService.updateLocalCLITimeoutSeconds(newValue)
        }

        Text("Available env: VOICEINK_SYSTEM_PROMPT, VOICEINK_USER_PROMPT, VOICEINK_FULL_PROMPT. Sotto also writes VOICEINK_FULL_PROMPT to stdin.")
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if !aiService.isAPIKeyValid {
            Text("Load a template or enter a command to enable Local CLI enhancement.")
                .font(.caption)
                .foregroundColor(Palette.warn)
        }
    }

    // MARK: - Foundation Models

    @ViewBuilder
    private var foundationModelsExpanded: some View {
        if #available(macOS 26.0, *) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AFMProvider.isAvailable ? Palette.success : Palette.warn)
                    .frame(width: 8, height: 8)
                Text(AFMProvider.isAvailable
                     ? "Apple Intelligence ready — no key required."
                     : "Apple Intelligence is not ready on this device.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.brandAcid)
                    .frame(width: 8, height: 8)
                Text("Requires macOS 26 or later.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Custom

    @ViewBuilder
    private var customExpanded: some View {
        TextField("API Endpoint URL", text: $aiService.customBaseURL,
                  prompt: Text("e.g. https://api.openai.com/v1/chat/completions"))
            .textFieldStyle(.roundedBorder)

        TextField("Model Name", text: $aiService.customModel,
                  prompt: Text("e.g. gemini-3.1-pro-preview, gpt-oss-120b"))
            .textFieldStyle(.roundedBorder)

        if aiService.isAPIKeyValid {
            HStack {
                Text("API Key Set")
                    .font(.system(size: 12))
                Spacer()
                Text("••••••••")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                Button("Remove", role: .destructive) {
                    aiService.clearAPIKey()
                    pendingKey = ""
                    verifyState = .idle
                    verifyMessage = nil
                }
                .controlSize(.small)
            }
            HStack {
                Spacer()
                Button(action: testConnection) {
                    HStack(spacing: 4) {
                        if verifyState == .verifying {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.shield")
                        }
                        Text("Test Connection")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .controlSize(.small)
                .disabled(verifyState == .verifying)
            }
        } else {
            SecureField("API Key", text: $pendingKey)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button(action: saveAndVerify) {
                    HStack(spacing: 4) {
                        if verifyState == .verifying {
                            ProgressView().controlSize(.small)
                        }
                        Text("Verify and Save")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .disabled(aiService.customBaseURL.isEmpty || aiService.customModel.isEmpty || pendingKey.isEmpty || verifyState == .verifying)
            }
        }

        verifyResultLabel
    }

    // MARK: - OpenRouter

    @ViewBuilder
    private var openRouterExpanded: some View {
        if aiService.availableModels.isEmpty {
            HStack {
                Text("No models loaded")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { Task { await aiService.fetchOpenRouterModels() } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .controlSize(.small)
            }
        } else {
            HStack {
                Picker("Model", selection: Binding(
                    get: { aiService.currentModel },
                    set: { aiService.selectModel($0) }
                )) {
                    ForEach(aiService.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                Button(action: { Task { await aiService.fetchOpenRouterModels() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .controlSize(.small)
                .help("Refresh model list")
            }
        }
    }

    // MARK: - Actions

    private func toggleExpand() {
        withAnimation(motion.reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)) {
            if isExpanded {
                expandedProvider = nil
            } else {
                expandedProvider = provider
                onActivate()
                onCardAppear()
            }
        }
    }

    private func onCardAppear() {
        if provider == .ollama, isExpanded || isActive {
            refreshOllama()
        }
        if provider == .localCLI, isExpanded || isActive {
            syncLocalCLIStateFromService()
        }
    }

    private func saveAndVerify() {
        verifyState = .verifying
        verifyMessage = nil
        let key = pendingKey
        aiService.saveAPIKey(key) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    verifyState = .success
                    pendingKey = ""
                } else {
                    verifyState = .failure
                    verifyMessage = errorMessage ?? "Verification failed."
                }
            }
        }
    }

    private func testConnection() {
        verifyState = .verifying
        verifyMessage = nil
        let key = APIKeyManager.shared.getAPIKey(forProvider: provider.rawValue) ?? ""
        guard !key.isEmpty else {
            verifyState = .failure
            verifyMessage = "No saved API key to test."
            return
        }
        aiService.verifyAPIKey(key) { isValid, errorMessage in
            DispatchQueue.main.async {
                if isValid {
                    verifyState = .success
                } else {
                    verifyState = .failure
                    verifyMessage = errorMessage ?? "Connection failed."
                }
            }
        }
    }

    private func refreshOllama() {
        isCheckingOllama = true
        verifyMessage = nil
        verifyState = .idle
        aiService.checkOllamaConnection { connected in
            if connected {
                Task {
                    let models = await aiService.fetchOllamaModels()
                    await MainActor.run {
                        ollamaModels = models
                        isCheckingOllama = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    ollamaModels = []
                    isCheckingOllama = false
                    verifyState = .failure
                    verifyMessage = "Could not reach Ollama. Check it is running and the base URL is correct."
                }
            }
        }
    }

    private func syncLocalCLIStateFromService() {
        isSyncingLocalCLIState = true
        localCLICommandTemplate = aiService.localCLICommandTemplate
        localCLITimeoutSeconds = aiService.localCLITimeoutSeconds
        DispatchQueue.main.async {
            isSyncingLocalCLIState = false
        }
    }

    // MARK: - Helpers

    private var apiKeyURL: URL? {
        switch provider {
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://makersuite.google.com/app/apikey")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        case .elevenLabs: return URL(string: "https://elevenlabs.io/speech-synthesis")
        case .deepgram: return URL(string: "https://console.deepgram.com/api-keys")
        case .soniox: return URL(string: "https://console.soniox.com/")
        case .speechmatics: return URL(string: "https://portal.speechmatics.com/manage-access/")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .cerebras: return URL(string: "https://cloud.cerebras.ai/")
        default: return nil
        }
    }
}

