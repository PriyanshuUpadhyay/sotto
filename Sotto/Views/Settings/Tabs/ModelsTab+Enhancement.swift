import SwiftUI

extension ModelsTab {
    // MARK: - Enhancement (flat: level + on-device provider + prompts)

    func statusText(for model: GGUFModelEntry) -> String {
        switch ggufDownloadManager.state(for: model.slug) {
        case .downloading:
            let pct = Int(ggufDownloadManager.progress(for: model.slug) * 100)
            return "Downloading… \(pct)%"
        case .paused:
            let pct = Int(ggufDownloadManager.progress(for: model.slug) * 100)
            return "Paused · \(pct)%"
        case .failed(let err):
            return "Failed: \(err)"
        case .idle:
            return downloadedGGUFSlugs.contains(model.slug) ? "Downloaded" : "Not downloaded"
        }
    }

    func download(_ model: GGUFModelEntry) {
        ggufDownloadManager.start(model.slug)
    }

    func delete(_ model: GGUFModelEntry) {
        alertTitle = "Delete Model"
        alertMessage = "Are you sure you want to delete the model '\(model.displayName)'?"
        deleteActionClosure = {
            Task {
                ggufDownloadManager.cancel(model.slug)
                try? GGUFModelRegistry.deleteModel(model.slug)
                await MainActor.run {
                    refreshGGUFStatus()
                    AIService.resetGGUF()
                    NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
                }
            }
        }
        isDeleteConfirmation = true
        isShowingDeleteAlert = true
    }

    func use(_ model: GGUFModelEntry) {
        enhancementGGUFModelSlug = model.slug
        enhancementProvider = AIProvider.localGGUF.rawValue
        AIService.resetGGUF()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    func refreshGGUFStatus() {
        downloadedGGUFSlugs = Set(
            GGUFModelRegistry.curated.filter { GGUFModelRegistry.isDownloaded($0.slug) }.map(\.slug)
        )
    }

    func ggufModelRow(_ model: GGUFModelEntry) -> some View {
        let state = ggufDownloadManager.state(for: model.slug)
        let isDownloaded = downloadedGGUFSlugs.contains(model.slug)
        let isInUse = (enhancementProvider == AIProvider.localGGUF.rawValue)
            && (enhancementGGUFModelSlug == model.slug)
            && isDownloaded

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.ui(11, weight: .medium))
                    .foregroundColor(Palette.inkSecondary)
                Text("\(model.diskSize) · \(model.licenseNote) · \(statusText(for: model))")
                    .font(.ui(11))
                    .foregroundColor(Palette.inkSecondary)
            }
            Spacer()
            if state == .downloading || state == .paused {
                ProgressView(value: ggufDownloadManager.progress(for: model.slug), total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                    .controlSize(.small)

                if state == .downloading {
                    Button("Pause") {
                        ggufDownloadManager.pause(model.slug)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Resume") {
                        ggufDownloadManager.resume(model.slug)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("Cancel") {
                    ggufDownloadManager.cancel(model.slug)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if isDownloaded {
                Button(isInUse ? "In use" : "Use") {
                    use(model)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Delete") {
                    delete(model)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Download") {
                    download(model)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.top, 4)
    }

    var enhancementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                iconSystemName: "wand.and.stars",
                iconTint: Brand.tint,
                title: "Enhancement",
                subtitle: "Clean transcripts on-device before pasting.",
                statusText: enhancementService.isEnhancementEnabled ? "On" : "Off",
                statusTone: enhancementService.isEnhancementEnabled ? .positive : .neutral
            ) {
                Toggle(isOn: Binding(
                    get: { enhancementService.isEnhancementEnabled },
                    set: { enhancementService.isEnhancementEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clean up transcripts with AI")
                            .font(.ui(12, weight: .semibold))
                        Text("Removes fillers and adds punctuation in languages supported by Apple Intelligence. Hindi is not supported. Off pastes the raw transcript.")
                            .font(.ui(11))
                            .foregroundColor(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $isConciseEnhancementEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Concise")
                            .font(.ui(12, weight: .semibold))
                        Text("Also drops crutch words such as \"basically\", \"actually\", \"that particular\", and a leading \"So,\" or \"Okay,\". Only deletes words; never rewrites.")
                            .font(.ui(11))
                            .foregroundColor(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .disabled(!enhancementService.isEnhancementEnabled)
            }

            SettingsCard(
                iconSystemName: "cpu",
                iconTint: Brand.tint,
                title: "Enhancement model",
                subtitle: "Choose which on-device model cleans your transcripts."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Enhancement model", selection: $enhancementProvider) {
                        ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                            Text(provider.rawValue)
                                .tag(provider.rawValue)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: enhancementProvider) { _ in
                        AIService.resetGGUF()
                        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
                    }
                    .onChange(of: enhancementGGUFModelSlug) { _ in
                        AIService.resetGGUF()
                        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
                    }

                    if enhancementProvider == AIProvider.localGGUF.rawValue && !downloadedGGUFSlugs.contains(enhancementGGUFModelSlug) {
                        Text("Selected local model is not downloaded; falling back to Apple Foundation Models.")
                            .font(.ui(11))
                            .foregroundColor(Palette.inkSecondary)
                    }

                    ForEach(GGUFModelRegistry.curated) { model in
                        ggufModelRow(model)
                    }
                }
            }
        }
        .onAppear {
            refreshGGUFStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AppSettingsDidChange)) { _ in
            refreshGGUFStatus()
        }
    }
}
