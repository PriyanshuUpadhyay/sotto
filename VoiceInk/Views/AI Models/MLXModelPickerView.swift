import SwiftUI

struct MLXModelPickerView: View {
    @EnvironmentObject private var aiService: AIService
    @AppStorage("mlx_selected_model_id") private var selectedModelId: String = ""

    @State private var statuses: [String: MLXModelStatus] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MLX Model")
                .font(.headline)

            Text("Models live under Application Support and are not auto-downloaded; pick one and click Download.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(MLXModelRegistry.curated) { model in
                modelRow(model)
                    .padding(.vertical, 4)
            }
        }
        .task { refreshAllStatuses() }
    }

    @ViewBuilder
    private func modelRow(_ model: MLXModelEntry) -> some View {
        let isActive = selectedModelId == model.id
        let isDownloaded = statuses[model.id] == .downloaded

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName).font(.body)
                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                Text("\(String(format: "%.1f", model.approximateSizeGB)) GB · \(model.notes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            useButton(for: model, isDownloaded: isDownloaded, isActive: isActive)
            statusControl(for: model)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15),
                        lineWidth: isActive ? 1.5 : 1)
        )
    }

    @ViewBuilder
    private func useButton(for model: MLXModelEntry, isDownloaded: Bool, isActive: Bool) -> some View {
        if isActive {
            EmptyView()
        } else if isDownloaded {
            Button("Use") {
                selectedModelId = model.id
                aiService.notifyMLXSelectionChanged()
                aiService.refreshAPIKeyValidity()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func statusControl(for model: MLXModelEntry) -> some View {
        switch statuses[model.id] ?? .notDownloaded {
        case .notDownloaded:
            Button("Download") { Task { await download(model) } }
                .buttonStyle(.borderedProminent)
        case .downloading(let fraction):
            ProgressView(value: fraction)
                .frame(width: 100)
        case .downloaded:
            Button("Delete") { delete(model) }
                .buttonStyle(.borderless)
        case .failed(let msg):
            VStack(alignment: .trailing, spacing: 2) {
                Text("Failed").font(.caption).foregroundStyle(.red)
                Text(msg).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Button("Retry") { Task { await download(model) } }
                    .controlSize(.small)
            }
        }
    }

    private func refreshAllStatuses() {
        for model in MLXModelRegistry.curated {
            statuses[model.id] = MLXModelDownloader.status(for: model.id)
        }
        // First-load auto-activate: if user has a downloaded model but no selection,
        // pick the first downloaded one. Covers the case where they downloaded in a
        // previous session but never clicked the (previously cryptic) toggle.
        if selectedModelId.isEmpty {
            if let firstDownloaded = MLXModelRegistry.curated.first(where: { statuses[$0.id] == .downloaded }) {
                selectedModelId = firstDownloaded.id
                aiService.notifyMLXSelectionChanged()
                aiService.refreshAPIKeyValidity()
            }
        }
    }

    private func download(_ model: MLXModelEntry) async {
        await MainActor.run { statuses[model.id] = .downloading(fraction: 0) }
        do {
            try await MLXModelDownloader.download(
                model.id,
                approximateSizeGB: model.approximateSizeGB
            ) { fraction in
                Task { @MainActor in
                    statuses[model.id] = .downloading(fraction: fraction)
                }
            }
            await MainActor.run {
                statuses[model.id] = .downloaded
                // Auto-activate if no model is currently selected — saves the user
                // a manual click and the "I downloaded but enhancement still doesn't work" trap.
                if selectedModelId.isEmpty {
                    selectedModelId = model.id
                    aiService.notifyMLXSelectionChanged()
                }
                aiService.refreshAPIKeyValidity()
            }
        } catch {
            await MainActor.run { statuses[model.id] = .failed(error.localizedDescription) }
        }
    }

    private func delete(_ model: MLXModelEntry) {
        do {
            try MLXModelDownloader.delete(model.id)
            statuses[model.id] = .notDownloaded
            if selectedModelId == model.id {
                selectedModelId = ""
                aiService.notifyMLXSelectionChanged()
            }
            aiService.refreshAPIKeyValidity()
        } catch {
            statuses[model.id] = .failed(error.localizedDescription)
        }
    }
}
