import SwiftUI

// MARK: - EnhancementProviderSection
//
// W14F UI redesign — splits the old `APIKeyManagementView` 2-col gallery
// into:
//
//   • `ActiveEnhancementProviderCard`  — focal "ACTIVE PROVIDER" card pinned
//     to the top of the Enhancement tab. Reuses `ProviderCard` but auto-
//     expands to the currently selected provider so its config (key field,
//     model picker, MLX downloader, Ollama URL, …) is visible by default.
//
//   • `OtherEnhancementProvidersAccordion` — collapsed-by-default
//     `DisclosureGroup` listing every non-active provider as a one-column
//     stack of `ProviderCard`s. Tapping a row expands its full config in
//     place and activates the provider via the existing `onActivate` hook.
//     Once activated, the provider naturally migrates out of the accordion
//     and into the focal card on the next render.
//
// Wiring preserved:
//   - `aiService.selectedProvider` is the only mutated state.
//   - `APIKeyManagementView.galleryProviders` is reused as the source of
//     truth for which providers belong on the Enhancement tab (excludes
//     speech-only providers, gates Foundation Models on macOS 26+).
//   - `ProviderCard` is unchanged — same expand/activate/save semantics.
//
// Hosted by `ModelsView`'s Enhancement tab (W14F).

struct ActiveEnhancementProviderCard: View {
    @EnvironmentObject private var aiService: AIService

    /// Bound to ProviderCard's expand state. Initialised to the active
    /// provider on appear and re-synced whenever `selectedProvider` changes
    /// (e.g. user activates a different provider from the accordion).
    @State private var expandedProvider: AIProvider?

    var body: some View {
        let provider = aiService.selectedProvider
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel
            ProviderCard(
                provider: provider,
                expandedProvider: $expandedProvider,
                onActivate: { aiService.selectedProvider = provider }
            )
        }
        .onAppear {
            if expandedProvider != provider {
                expandedProvider = provider
            }
        }
        .onChange(of: aiService.selectedProvider) { _, newProvider in
            // Keep the focal card auto-expanded when the active provider
            // changes (e.g. user picks a different one from the accordion).
            expandedProvider = newProvider
        }
    }

    /// SF Mono uppercase label (same vocabulary as the cluster's chip keys
    /// and `APIKeyManagementView`'s section labels).
    private var sectionLabel: some View {
        HStack(spacing: 8) {
            Text("ACTIVE PROVIDER")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundColor(Palette.accent)
            Rectangle()
                .fill(Palette.hairlineSoft)
                .frame(height: 1)
        }
    }
}

struct OtherEnhancementProvidersAccordion: View {
    @EnvironmentObject private var aiService: AIService

    @State private var isExpanded: Bool = false
    @State private var expandedProvider: AIProvider?

    /// All gallery providers minus the currently active one. Configured
    /// (connected) providers appear first, then unconfigured — alphabetical
    /// inside each group. Mirrors `APIKeyManagementView`'s ordering.
    private var otherProviders: [AIProvider] {
        let active = aiService.selectedProvider
        let connectedSet = Set(aiService.connectedProviders)
        let pool = APIKeyManagementView.galleryProviders.filter { $0 != active }
        let configured = pool
            .filter { connectedSet.contains($0) }
            .sorted { ProviderChipStyle.displayName(for: $0) < ProviderChipStyle.displayName(for: $1) }
        let unconfigured = pool
            .filter { !connectedSet.contains($0) }
            .sorted { ProviderChipStyle.displayName(for: $0) < ProviderChipStyle.displayName(for: $1) }
        return configured + unconfigured
    }

    private var configuredCount: Int {
        let active = aiService.selectedProvider
        let connectedSet = Set(aiService.connectedProviders)
        return APIKeyManagementView.galleryProviders
            .filter { $0 != active && connectedSet.contains($0) }
            .count
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        isExpanded.toggle()
                    }
                }
                .padding(14)

            if isExpanded {
                Divider()
                    .background(Palette.hairlineSoft)
                    .padding(.horizontal, 14)
                VStack(spacing: 10) {
                    ForEach(otherProviders, id: \.self) { provider in
                        ProviderCard(
                            provider: provider,
                            expandedProvider: $expandedProvider,
                            onActivate: { aiService.selectedProvider = provider }
                        )
                    }
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            shape.fill(.ultraThinMaterial)
        )
        .overlay(
            shape.stroke(Palette.hairline, lineWidth: 1)
        )
        .clipShape(shape)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            // Pictogram tile (same shape as ProviderCard's tile, neutral tint).
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.neutral.opacity(0.18))
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.5)
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Other providers")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            Text("\(otherProviders.count) HIDDEN")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(0.06 * 9.5)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().stroke(Palette.hairlineSoft, lineWidth: 0.5))

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
    }

    private var subtitleText: String {
        let configured = configuredCount
        if configured == 0 {
            return "Tap to browse and configure additional providers."
        } else if configured == 1 {
            return "1 configured · tap to switch active provider."
        } else {
            return "\(configured) configured · tap to switch active provider."
        }
    }
}
