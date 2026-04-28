import SwiftUI

// MARK: - MLXModelPickerView
//
// On-device model picker rendered inside `ProviderCard`'s `.mlx` expanded
// arm. W6 re-skin: rows show speed + quality ratings + expected latency
// chips inheriting the glass vocabulary; experimental tier surfaces a
// caution chip. W9: chip strip wraps via FlowLayout on narrow card widths
// to recover the Quality chip clipping reported in the post-W8 handoff.
// Spec §5 row W6 + W6 plan
// `docs/superpowers/plans/W6-mlx-quality-and-segregation.md` + W9 plan
// `docs/superpowers/plans/W9-mlx-chip-overflow.md`.

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
        let latency = model.expectedLatencySeconds

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(model.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                if isActive { activeChip }
                if model.isExperimental { experimentalChip }
                Spacer()
                useButton(for: model, isDownloaded: isDownloaded, isActive: isActive)
                statusControl(for: model)
            }

            // W9: chip strip wraps to a second row on narrow ProviderCard widths
            // (Quality chip was clipping at default width). FlowLayout's default
            // spacing(6) matches the prior HStack inter-chip gap and doubles as
            // the inter-row gap. Spacer() is dropped — FlowLayout treats Spacer
            // as a zero-width flow item, so the size annotation flows as the
            // trailing item instead. Spec §5 row W6; plan
            // docs/superpowers/plans/W9-mlx-chip-overflow.md.
            FlowLayout(spacing: 6) {
                ratingChip(label: "Speed", value: model.speedRating)
                ratingChip(label: "Quality", value: model.qualityRating)
                latencyChip(min: latency.lowerBound, max: latency.upperBound)
                Text("\(String(format: "%.1f", model.approximateSizeGB)) GB")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.06 * 10.5)
                    .foregroundColor(Palette.onyxMute)
            }

            Text(model.notes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? Palette.accent.opacity(0.10) : Color.clear)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isActive ? Palette.accent.opacity(0.55) : Palette.hairline,
                        lineWidth: isActive ? 1.5 : 1)
        )
    }

    private var activeChip: some View {
        Text("ACTIVE")
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(0.06 * 9.5)
            .foregroundColor(Palette.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Palette.accent.opacity(0.16)))
            .overlay(Capsule().stroke(Palette.accent.opacity(0.42), lineWidth: 0.5))
    }

    private var experimentalChip: some View {
        Text("EXPERIMENTAL")
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(0.06 * 9.5)
            .foregroundColor(Palette.warn)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Palette.warn.opacity(0.16)))
            .overlay(Capsule().stroke(Palette.warn.opacity(0.42), lineWidth: 0.5))
    }

    private func ratingChip(label: String, value: Int) -> some View {
        Text("\(label) \(value)/10")
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .tracking(0.06 * 10.5)
            .foregroundColor(Palette.onyxFg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(Palette.hairline, lineWidth: 0.5)
            )
    }

    private func latencyChip(min: Double, max: Double) -> some View {
        let text = "\(formatSecs(min))-\(formatSecs(max))s"
        return Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .tracking(0.06 * 10.5)
            .foregroundColor(Palette.onyxMute)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.white.opacity(0.04))
            )
            .overlay(
                Capsule().stroke(Palette.hairlineSoft, lineWidth: 0.5)
            )
    }

    private func formatSecs(_ value: Double) -> String {
        String(format: "%.0f", value)
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
                .controlSize(.small)
        case .downloading(let fraction):
            downloadProgressChip(fraction: fraction)
        case .downloaded:
            Button("Delete") { delete(model) }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
        case .failed(let msg):
            VStack(alignment: .trailing, spacing: 2) {
                Text("Failed")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(0.06 * 10.5)
                    .foregroundColor(Palette.accent)
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 140, alignment: .trailing)
                Button("Retry") { Task { await download(model) } }
                    .controlSize(.small)
            }
        }
    }

    /// W6 chip-vocabulary download progress — replaces the bare ProgressView.
    /// Width 110pt; `Palette.accent` fills the leading portion proportional
    /// to `fraction`; the trailing remainder shows the hairline track. Motion
    /// matches `Animation.clusterFadeReduced` (0.18s linear) so the bar reads
    /// the same as the cluster's collapse vocabulary. Spec §5#6.
    private func downloadProgressChip(fraction: Double) -> some View {
        let clamped = max(0.0, min(1.0, fraction))
        let pct = Int(clamped * 100)
        return GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .overlay(Capsule().stroke(Palette.hairline, lineWidth: 0.5))
                Capsule()
                    .fill(Palette.accent.opacity(0.55))
                    .frame(width: width * clamped)
                    .animation(.linear(duration: 0.18), value: clamped)
                Text("\(pct)%")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(0.06 * 9.5)
                    .foregroundColor(Palette.onyxFg)
                    .padding(.leading, 8)
            }
        }
        .frame(width: 110, height: 18)
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
