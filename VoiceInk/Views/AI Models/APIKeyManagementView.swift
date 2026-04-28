import SwiftUI
import LLMkit

// MARK: - APIKeyManagementView
//
// Provider gallery — 2-column glass grid of `ProviderCard`s, one per AIProvider
// (speech-only providers excluded). Per spec §3.7 the AI Models tab now reads
// as a portfolio of provider tiles instead of a one-provider-at-a-time picker.
//
// Behavior:
//   - Tapping a card expands it AND sets `aiService.selectedProvider = card.provider`
//     (via `onActivate`). This keeps `aiService.saveAPIKey` / `verifyAPIKey`
//     wired to the existing single-provider implementation without refactor.
//   - `expandedProvider` state is owned here so only one card is open at a time.
//   - Section header reuses `SettingsSectionHeader` for consistency with other
//     settings panes.

struct APIKeyManagementView: View {
    @EnvironmentObject private var aiService: AIService
    @State private var expandedProvider: AIProvider?

    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    /// Providers worth showing in the enhancement gallery. Excludes
    /// speech-only providers (they live in the transcription model gallery)
    /// and gates Foundation Models on macOS 26+.
    static var galleryProviders: [AIProvider] {
        let excluded: Set<AIProvider> = [.elevenLabs, .deepgram, .soniox, .speechmatics]
        return AIProvider.allCases.filter { provider in
            if excluded.contains(provider) { return false }
            if provider == .foundationModels {
                if #available(macOS 26.0, *) {
                    return true
                } else {
                    return false
                }
            }
            return true
        }
    }

    /// Subset of `galleryProviders` that the user has configured (API key
    /// present, MLX model downloaded, ollama reachable, etc.). Driven by
    /// `aiService.connectedProviders` — the existing single source of truth
    /// in `AIService.swift:289-309`. Sorted: the active provider first if
    /// it's in the configured set, then alphabetical by display name.
    private var configuredProviders: [AIProvider] {
        let connectedSet = Set(aiService.connectedProviders)
        let gallery = APIKeyManagementView.galleryProviders.filter { connectedSet.contains($0) }
        let active = aiService.selectedProvider
        if gallery.contains(active) {
            let rest = gallery.filter { $0 != active }
                .sorted { ProviderChipStyle.displayName(for: $0) < ProviderChipStyle.displayName(for: $1) }
            return [active] + rest
        }
        return gallery.sorted { ProviderChipStyle.displayName(for: $0) < ProviderChipStyle.displayName(for: $1) }
    }

    /// Complement of `configuredProviders` over `galleryProviders`. Sorted
    /// alphabetical by display name.
    private var unconfiguredProviders: [AIProvider] {
        let connectedSet = Set(aiService.connectedProviders)
        return APIKeyManagementView.galleryProviders
            .filter { !connectedSet.contains($0) }
            .sorted { ProviderChipStyle.displayName(for: $0) < ProviderChipStyle.displayName(for: $1) }
    }

    /// Section label rendered above each grid. SF Mono uppercase tracking
    /// 0.06em — same vocabulary as the cluster's chip keys (spec §1).
    private func sectionLabel(_ text: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundColor(Palette.onyxMute)
            Text("\(count)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundColor(Palette.onyxMute.opacity(0.7))
            Spacer()
        }
        .padding(.top, 6)
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Compact identity preview — chip for the active provider.
                ProviderChip(
                    provider: aiService.selectedProvider,
                    model: providerChipModel,
                    connected: providerChipConnected
                )
                .padding(.bottom, 4)

                // CONFIGURED — providers with credentials / downloaded models.
                let configured = configuredProviders
                if !configured.isEmpty {
                    sectionLabel("CONFIGURED", count: configured.count)
                    LazyVGrid(columns: APIKeyManagementView.columns, spacing: 12) {
                        ForEach(configured, id: \.self) { provider in
                            ProviderCard(
                                provider: provider,
                                expandedProvider: $expandedProvider,
                                onActivate: { aiService.selectedProvider = provider }
                            )
                        }
                    }
                } else {
                    Text("No providers configured yet. Pick one below to add a key or download a local model.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }

                // UNCONFIGURED — providers without credentials / no model downloaded.
                let unconfigured = unconfiguredProviders
                if !unconfigured.isEmpty {
                    sectionLabel("AVAILABLE", count: unconfigured.count)
                    LazyVGrid(columns: APIKeyManagementView.columns, spacing: 12) {
                        ForEach(unconfigured, id: \.self) { provider in
                            ProviderCard(
                                provider: provider,
                                expandedProvider: $expandedProvider,
                                onActivate: { aiService.selectedProvider = provider }
                            )
                            .opacity(0.85)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            SettingsSectionHeader(
                icon: "sparkles.rectangle.stack",
                title: "AI Provider Integration",
                subtitle: "Pick the model that shapes enhanced transcripts.",
                accent: Palette.accent,
                statusText: providerStatusText,
                statusTone: providerStatusTone
            )
        }
        .onAppear {
            // Pre-expand the active provider so users land on a configurable card.
            if expandedProvider == nil {
                expandedProvider = aiService.selectedProvider
            }
        }
    }

    // MARK: - Active-provider chip helpers

    private var providerChipModel: String? {
        switch aiService.selectedProvider {
        case .foundationModels: return nil
        case .custom:
            return aiService.customModel.isEmpty ? nil : aiService.customModel
        case .ollama:
            let model = UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? ""
            return model.isEmpty ? nil : model
        default:
            return aiService.currentModel.isEmpty ? nil : aiService.currentModel
        }
    }

    private var providerChipConnected: Bool {
        switch aiService.selectedProvider {
        case .ollama:
            // No live ollama state at this layer — fall back to "key" semantics
            // (always considered "may be" until the card is opened and pinged).
            return aiService.isAPIKeyValid
        case .foundationModels:
            if #available(macOS 26.0, *) { return FoundationModelsProvider.isAvailable }
            return false
        default:
            return aiService.isAPIKeyValid
        }
    }

    // MARK: - Section header status

    private var providerStatusText: String? {
        // Filter the numerator to the gallery set — `aiService.connectedProviders`
        // also counts speech-only keys (ElevenLabs/Deepgram/Soniox/Speechmatics)
        // which are NOT shown in this gallery (they live in the transcription
        // model panel). Without filtering a user with 4 speech keys saw a
        // misleading "4 of 11 connected" on the AI Provider section.
        let gallerySet = Set(APIKeyManagementView.galleryProviders)
        let connected = aiService.connectedProviders.filter { gallerySet.contains($0) }.count
        let total = APIKeyManagementView.galleryProviders.count
        return "\(connected) of \(total)"
    }

    private var providerStatusTone: SettingsSectionHeader.StatusTone {
        let gallerySet = Set(APIKeyManagementView.galleryProviders)
        return aiService.connectedProviders.contains(where: { gallerySet.contains($0) })
            ? .positive : .neutral
    }
}

// MARK: - StatusPill
//
// Small capsule-pill replacing the plain dot-and-text "Connected" / "Disconnected"
// labels. Uses the Halo palette so connection state reads consistently with the
// recorder's halo glow language (success-green / warn-amber / neutral-gray).
//
// Retained from the pre-gallery view: still consumed by other settings panes
// that surface connection state inline.

struct StatusPill: View {
    enum Tone {
        case positive   // green — connected, available
        case negative   // red-tinted — disconnected, error
        case neutral    // gray — no signal
        case warning    // amber — degraded, checking

        var color: Color {
            switch self {
            case .positive: return Palette.success
            case .negative: return Palette.accent
            case .neutral:  return Palette.neutral
            case .warning:  return Palette.warn
            }
        }
    }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tone.color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(tone.color.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(tone.color.opacity(0.32), lineWidth: 0.5)
        )
    }
}
