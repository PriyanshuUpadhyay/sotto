import SwiftUI
import AVFoundation
import AppKit

// MARK: - TranscriptionDetailView (P3.A)
//
// History detail surface, rebuilt as a `GlassCard` hero per spec §3.5:
//
//   ┌─ glass card ──────────────────────────────────────╮
//   │ [thumbnail]   2026-04-28 · 11:42                  │
//   │ [ProviderChip: CLAUDE]   2:14                     │
//   │ ───────────────────────────                       │
//   │ ▶ ━━━━●━━━━━━━━━━━  0:32 / 2:14                   │
//   │ Original ───────────                              │
//   │ "umm so the dynamic island feels great…"          │
//   │ Enhanced ───────────                              │
//   │ "The dynamic island feels great."                 │
//   │ [Copy] [Re-transcribe] [Re-enhance] [Delete]      │
//   ╰───────────────────────────────────────────────────╯
//
// Audio playback owns its own `AudioPlayerManager` (mirrors AudioPlayerView's
// existing pattern) so retranscribe / re-enhance can mutate the record
// in-place without round-tripping through a child player view.
//
// Provider chip is inferred from `transcription.aiEnhancementModelName` —
// the record stores model names (e.g. "claude-3-5-sonnet…"), not provider
// IDs, so we map by substring. Returns nil when no enhancement happened.

struct TranscriptionDetailView: View {
    let transcription: Transcription
    var onInfoTap: (() -> Void)?
    var onDelete: (() -> Void)?

    @StateObject private var playerManager = AudioPlayerManager()
    @State private var isRetranscribing = false
    @State private var isReEnhancing = false
    @State private var statusMessage: StatusMessage?
    @State private var showPromptPopover = false

    @EnvironmentObject private var engine: VoiceInkEngine
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext

    // MARK: - Body

    var body: some View {
        ScrollView {
            GlassCard(cornerRadius: 22, padding: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    headerRow
                    if let url = audioURL {
                        sectionDivider
                        AudioTimelineView(
                            audioFile: url,
                            duration: playerManager.duration,
                            currentTime: $playerManager.currentTime,
                            isPlaying: playerManager.isPlaying,
                            onPlayPause: togglePlayback,
                            onSeek: { playerManager.seek(to: $0) }
                        )
                    }
                    sectionDivider
                    textPanes
                    sectionDivider
                    actionsRow
                    if let msg = statusMessage {
                        Text(msg.text)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(msg.isError ? Palette.accent : Palette.success)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let u = audioURL { playerManager.loadAudio(from: u) }
        }
        .onDisappear { playerManager.cleanup() }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                Text(transcription.timestamp,
                     format: .dateTime.year().month(.abbreviated).day().hour().minute())
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                HStack(spacing: 10) {
                    if let provider = inferredProvider {
                        ProviderChip(
                            provider: provider,
                            model: transcription.aiEnhancementModelName,
                            connected: false
                        )
                    } else if let modelName = transcription.transcriptionModelName {
                        // No enhancement — surface the transcription model so the
                        // header doesn't go empty.
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Palette.accent)
                            Text(modelName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if transcription.duration > 0 {
                        durationPill
                    }
                }
            }
            Spacer(minLength: 0)
            if let onInfoTap {
                Button(action: onInfoTap) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("View metadata")
            }
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.accent.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Palette.accent.opacity(0.28), lineWidth: 0.5)
                )
                .frame(width: 48, height: 48)
            Image(systemName: audioURL != nil ? "waveform" : "doc.text.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Palette.accent)
        }
    }

    private var durationPill: some View {
        Text(transcription.duration.formatTiming())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.4)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Palette.neutral.opacity(0.14)))
            .overlay(Capsule().stroke(Palette.neutral.opacity(0.28), lineWidth: 0.5))
            .foregroundColor(.secondary)
    }

    // MARK: - Text panes

    private var textPanes: some View {
        VStack(alignment: .leading, spacing: 12) {
            textPane(label: "Original",
                     text: transcription.text,
                     accent: Palette.accent)
            if let enhanced = transcription.enhancedText, !enhanced.isEmpty {
                textPane(label: "Enhanced",
                         text: enhanced,
                         accent: Palette.accent)
            }
        }
    }

    private func textPane(label: String, text: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(0.6)
                Spacer()
                CopyIconButton(textToCopy: text)
            }
            ScrollView {
                Text(text)
                    .font(.system(size: 13, weight: .regular))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.20), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: 10) {
            actionButton(label: "Copy", icon: "doc.on.doc") {
                copyToClipboard()
            }
            if audioURL != nil {
                actionButton(
                    label: isRetranscribing ? "Retranscribing…" : "Re-transcribe",
                    icon: "arrow.clockwise",
                    isLoading: isRetranscribing
                ) {
                    retranscribe()
                }
                .disabled(isOperationInProgress)
            }
            if enhancementService.isEnhancementEnabled, enhancementService.isConfigured {
                promptPicker
                actionButton(
                    label: isReEnhancing ? "Re-enhancing…" : "Re-enhance",
                    icon: "wand.and.stars",
                    isLoading: isReEnhancing
                ) {
                    reEnhance()
                }
                .disabled(isOperationInProgress)
            }
            Spacer(minLength: 0)
            if onDelete != nil {
                actionButton(label: "Delete", icon: "trash", isDestructive: true) {
                    onDelete?()
                }
                .disabled(isOperationInProgress)
            }
        }
    }

    private var promptPicker: some View {
        Button(action: { showPromptPopover.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: enhancementService.activePrompt?.icon ?? "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text(enhancementService.activePrompt?.title ?? "Prompt")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 110)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.accent.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Palette.accent.opacity(0.25), lineWidth: 0.5)
            )
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPromptPopover, arrowEdge: .bottom) {
            EnhancementPromptPopover()
                .environmentObject(enhancementService)
        }
        .help("Select enhancement prompt")
    }

    private func actionButton(label: String,
                              icon: String,
                              isLoading: Bool = false,
                              isDestructive: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDestructive
                          ? Palette.accent.opacity(0.10)
                          : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isDestructive
                            ? Palette.accent.opacity(0.25)
                            : Color.primary.opacity(0.10),
                            lineWidth: 0.5)
            )
            .foregroundColor(isDestructive ? Palette.accent : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
    }

    private var audioURL: URL? {
        guard let s = transcription.audioFileURL,
              let u = URL(string: s),
              FileManager.default.fileExists(atPath: u.path)
        else { return nil }
        return u
    }

    private var isOperationInProgress: Bool {
        isRetranscribing || isReEnhancing
    }

    private var transcriptionService: AudioTranscriptionService {
        AudioTranscriptionService(modelContext: modelContext, engine: engine)
    }

    /// Best-effort provider inference from a stored model name. We don't
    /// have provenance on the record (only the model string), so this is
    /// substring-based — good enough for the chip in the header.
    private var inferredProvider: AIProvider? {
        guard let raw = transcription.aiEnhancementModelName?.lowercased() else { return nil }
        // OpenRouter prefixes "<vendor>/<model>" — match before claude/gpt/etc.
        // so we don't mis-tag e.g. "anthropic/claude-3" as direct Anthropic.
        if raw.contains("/") { return .openRouter }
        if raw.contains("claude") { return .anthropic }
        if raw.contains("gpt") || raw.hasPrefix("o1") || raw.hasPrefix("o3") || raw.hasPrefix("o4") {
            return .openAI
        }
        if raw.contains("gemini") { return .gemini }
        if raw.contains("groq") { return .groq }
        if raw.contains("cerebras") { return .cerebras }
        if raw.contains("mistral") || raw.contains("ministral") { return .mistral }
        if raw.contains("llama") || raw.contains("qwen") || raw.contains("phi") {
            return .ollama
        }
        if raw.contains("foundation") || raw.contains("apple") { return .foundationModels }
        if raw.contains("mlx") { return .mlx }
        return .custom
    }

    // MARK: - Actions

    private func togglePlayback() {
        playerManager.isPlaying ? playerManager.pause() : playerManager.play()
    }

    private func copyToClipboard() {
        let text = transcription.enhancedText ?? transcription.text
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        showStatus("Copied to clipboard", isError: false)
    }

    private func showStatus(_ text: String, isError: Bool) {
        let msg = StatusMessage(text: text, isError: isError)
        withAnimation(.easeInOut(duration: 0.2)) { statusMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            // Only clear if this status is still the active one.
            if statusMessage?.id == msg.id {
                withAnimation(.easeInOut(duration: 0.2)) { statusMessage = nil }
            }
        }
    }

    private func reEnhance() {
        guard enhancementService.isEnhancementEnabled, enhancementService.isConfigured else {
            showStatus("AI enhancement is not enabled or configured", isError: true)
            return
        }
        isReEnhancing = true
        Task {
            do {
                let (enhanced, dur, name) = try await enhancementService.enhance(transcription.text)
                await MainActor.run {
                    transcription.enhancedText = enhanced
                    transcription.aiEnhancementModelName = enhancementService.getAIService()?.currentModel
                    transcription.promptName = name
                    transcription.enhancementDuration = dur
                    transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                    transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                    try? modelContext.save()
                    isReEnhancing = false
                    showStatus("Re-enhancement successful", isError: false)
                }
            } catch {
                await MainActor.run {
                    isReEnhancing = false
                    showStatus(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func retranscribe() {
        guard let url = audioURL else { return }
        guard let model = engine.transcriptionModelManager.currentTranscriptionModel else {
            showStatus("No transcription model selected", isError: true)
            return
        }
        isRetranscribing = true
        Task {
            do {
                _ = try await transcriptionService.retranscribeAudio(from: url, using: model)
                await MainActor.run {
                    isRetranscribing = false
                    showStatus("Retranscription successful", isError: false)
                }
            } catch {
                await MainActor.run {
                    isRetranscribing = false
                    showStatus(error.localizedDescription, isError: true)
                }
            }
        }
    }
}

// MARK: - Supporting types

private struct StatusMessage: Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}
