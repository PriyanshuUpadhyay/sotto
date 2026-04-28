import SwiftUI
import SwiftData
import AppKit

// MARK: - MenuBarView (P2.B / spec §3.2)
//
// Adaptive Glass dropdown that replaces the stock SwiftUI `Menu` chrome.
// Hosted by `MenuBarExtra(... ) { MenuBarView() } .menuBarExtraStyle(.window)`
// in `VoiceInk.swift` — the `.window` style is required so a custom view
// (vs. an `NSMenu` of buttons) can render with the glass material + entry
// spring described in the spec layout block.
//
// Layout (top → bottom, per spec §3.2):
//   • Wordmark + version (mono).
//   • MODELS section — transcription chip + enhancement `ProviderChip`.
//   • AI ENHANCEMENT — label + `GlassSwitch` (replaces stock `Toggle`).
//   • PROMPT — `PromptChipPicker` (P2.A primitive).
//   • RECENT — 2 most recent transcriptions, italic 12pt, 1-line truncate.
//   • Settings + Quit row.
//
// Background: `HaloMaterial` direct (NOT `GlassCard`) — `GlassCard` carries
// the §3.3 hover-lift (4pt translate-y on cursor-enter) which is undesirable
// for a popover root since the card edge would clip against the popover
// window bounds. Same Adaptive Glass material vocabulary, no hover offset.
//
// Entry motion: scale 0.96 → 1.0 + opacity 0 → 1 over `Animation.haloExpand`
// (spec §2.4 — 0.38s). Driven by `visible` flipping in `.onAppear`.
//
// VoiceOver order: wordmark → version → models section → AI toggle →
// prompts → recent → buttons. No skipped focus zones (acceptance criterion).

struct MenuBarView: View {
    @EnvironmentObject var engine: VoiceInkEngine
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService

    @ObservedObject private var detector = GlassAppearanceDetector.shared
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared

    @State private var visible: Bool = false
    @State private var recentTranscriptions: [Transcription] = []

    private static let popoverWidth: CGFloat = 360
    private static let popoverHeight: CGFloat = 420
    private static let cornerRadius: CGFloat = 16

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)

        VStack(alignment: .leading, spacing: 16) {
            header
            modelsSection
            aiEnhancementToggle
            promptSection
            recentSection
            Spacer(minLength: 0)
            buttonRow
        }
        .padding(16)
        .frame(width: Self.popoverWidth, height: Self.popoverHeight, alignment: .topLeading)
        .background(
            HaloMaterial(
                shape: shape,
                phase: .hidden,
                appearance: detector.current
            )
        )
        .clipShape(shape)
        .scaleEffect(visible ? 1.0 : 0.96, anchor: .top)
        .opacity(visible ? 1.0 : 0.0)
        .animation(motion.reduceMotion ? nil : .haloExpand, value: visible)
        .onAppear {
            visible = true
            reloadRecents()
        }
        .onDisappear { visible = false }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("VoiceInk")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(100)

            Text("v\(appVersion)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .accessibilityLabel("Version \(appVersion)")
                .accessibilitySortPriority(99)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Models section

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("MODELS")
                .accessibilitySortPriority(90)

            VStack(alignment: .leading, spacing: 8) {
                modelRow(label: "TRANSCRIPTION") {
                    transcriptionModelChip
                }
                .accessibilitySortPriority(89)

                modelRow(label: "ENHANCEMENT") {
                    ProviderChip(
                        provider: aiService.selectedProvider,
                        model: aiService.currentModel,
                        connected: aiService.isAPIKeyValid
                    )
                }
                .accessibilitySortPriority(88)
            }
        }
    }

    private func modelRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.85))
                .frame(width: 96, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    /// Visual analog of `ProviderChip` for transcription models. `ProviderChip`
    /// is hardcoded to `AIProvider`, so we mirror the geometry locally rather
    /// than widening that primitive (P2.A reviewer focus: don't dilute chip
    /// semantics with non-AI providers).
    private var transcriptionModelChip: some View {
        let model = transcriptionModelManager.currentTranscriptionModel
        let displayName = model?.displayName ?? "None"
        return HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Palette.transcribe)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Palette.transcribe.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Palette.transcribe.opacity(0.32), lineWidth: 0.5)
                )

            Text(displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcription model: \(displayName)")
    }

    // MARK: - AI Enhancement toggle

    private var aiEnhancementToggle: some View {
        HStack(spacing: 12) {
            Text("AI ENHANCEMENT")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
            GlassSwitch(isOn: $enhancementService.isEnhancementEnabled)
                .accessibilityLabel("AI Enhancement")
        }
        .accessibilitySortPriority(80)
    }

    // MARK: - Prompt picker

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("PROMPT")
                .accessibilitySortPriority(70)

            PromptChipPicker(
                prompts: enhancementService.allPrompts,
                selectedID: Binding(
                    get: { enhancementService.selectedPromptId },
                    set: { newID in
                        if let id = newID,
                           let prompt = enhancementService.allPrompts.first(where: { $0.id == id }) {
                            enhancementService.setActivePrompt(prompt)
                        }
                    }
                )
            )
            .accessibilitySortPriority(69)
            // Disable + dim when AI Enhancement is off — the chips are the
            // selection surface for an inactive feature otherwise.
            .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.5)
            .allowsHitTesting(enhancementService.isEnhancementEnabled)
        }
    }

    // MARK: - Recent transcriptions

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("RECENT")
                .accessibilitySortPriority(60)

            if recentTranscriptions.isEmpty {
                Text("No transcriptions yet")
                    .font(.system(size: 12).italic())
                    .foregroundColor(.secondary.opacity(0.7))
                    .accessibilitySortPriority(59)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(recentTranscriptions.enumerated()), id: \.element.id) { index, t in
                        recentRow(t)
                            .accessibilitySortPriority(Double(59 - index))
                    }
                }
            }
        }
    }

    private func recentRow(_ t: Transcription) -> some View {
        let preview: String = {
            if let enhanced = t.enhancedText, !enhanced.isEmpty { return enhanced }
            return t.text
        }()
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("“\(preview)”")
                .font(.system(size: 12).italic())
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recent: \(preview)")
    }

    // MARK: - Buttons

    private var buttonRow: some View {
        HStack(spacing: 10) {
            glassButton("Settings") {
                menuBarManager.openMainWindowAndNavigate(to: "Settings")
            }
            .accessibilitySortPriority(20)
            .keyboardShortcut(",", modifiers: .command)

            glassButton("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .accessibilitySortPriority(19)
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func glassButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                // `Color.primary` resolves white-in-dark / black-in-light, so
                // the affordance stays visible on both onyx + light glass.
                // Hardcoded `Color.white` would render invisible against the
                // light variant (reviewer P2.B blocker).
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.7))
            .tracking(0.6)
            .accessibilityAddTraits(.isHeader)
    }

    /// Refresh the RECENT section. Called on appear; cheap (fetch limit 2).
    private func reloadRecents() {
        recentTranscriptions = LastTranscriptionService.getRecentTranscriptions(
            from: engine.modelContext,
            limit: 2
        )
    }
}
