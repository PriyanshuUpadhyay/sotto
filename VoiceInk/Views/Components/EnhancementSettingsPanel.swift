import SwiftUI
import AppKit

struct EnhancementSettingsPanel: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @AppStorage("SkipShortEnhancement") private var isSkipShortEnhancementEnabled = true
    @AppStorage("ShortEnhancementWordThreshold") private var shortEnhancementWordThreshold = 3
    @AppStorage("EnhancementTimeoutSeconds") private var enhancementTimeoutSeconds = 15
    @AppStorage("EnhancementRetryOnTimeout") private var retryOnTimeout = true
    @AppStorage("MLXIdleEvictSeconds") private var mlxIdleEvictSeconds = 1800
    @AppStorage("ForceMLXOverAFM") private var forceMLXOverAFM = false
    @AppStorage("PrewarmAFMEnhancement") private var prewarmAFMEnhancement = true

    /// W14 — wraps `AFMProvider.isAvailable` behind the required `#available`
    /// guard so toggle visibility checks can stay inline in the ViewBuilder.
    private var afmAvailable: Bool {
        if #available(macOS 26.0, *) { return AFMProvider.isAvailable }
        return false
    }
    @State private var isShortEnhancementExpanded = false
    @State private var isHandlingToggleChange = false
    @State private var didCopyTimingsPath = false

    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("Enhancement Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Palette.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .adaptiveGlassBackground(intensity: .panel)
            .overlay(
                Rectangle()
                    .fill(Palette.hairlineSoft)
                    .frame(height: 1),
                alignment: .bottom
            )

            // Content — flat sectionBlock VStack (no Form, no SettingsCard).
            // The popover IS the card; sections are dividers within it. See
            // W13.D plan §S2 — SettingsCard would double-layer over the
            // panel's existing `.adaptiveGlassBackground(intensity: .panel)`.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    cleanupLevelSection
                    contextSection
                    shortTranscriptionsSection
                    requestTimeoutSection

                    if enhancementService.aiService.selectedProvider == .mlx
                        || enhancementService.aiService.selectedProvider == .foundationModels {
                        onDeviceSection
                    }

                    shortcutsSection
                    lastSystemPromptSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .tint(Palette.accent)
    }

    // MARK: - Sections

    private var cleanupLevelSection: some View {
        sectionBlock(
            label: "CLEANUP LEVEL",
            info: "None pastes raw transcripts. Light removes fillers. Medium fixes grammar. High polishes for clarity."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $enhancementService.enhanceLevel) {
                    ForEach(EnhanceLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(enhancementService.enhanceLevel.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var contextSection: some View {
        sectionBlock(label: "CONTEXT") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $enhancementService.useClipboardContext) {
                    HStack(spacing: 4) {
                        Text("Clipboard Context")
                        InfoTip("Use clipboard text to understand context for better enhancement.")
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $enhancementService.useScreenCaptureContext) {
                    HStack(spacing: 4) {
                        Text("Screen Context")
                        InfoTip("Capture on-screen text to understand context for better enhancement.")
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    private var shortTranscriptionsSection: some View {
        sectionBlock(label: "SHORT TRANSCRIPTIONS") {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Toggle(isOn: Binding(
                        get: { isSkipShortEnhancementEnabled },
                        set: { newValue in
                            isHandlingToggleChange = true
                            isSkipShortEnhancementEnabled = newValue
                            if newValue {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShortEnhancementExpanded = true
                                }
                            } else {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShortEnhancementExpanded = false
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isHandlingToggleChange = false
                            }
                        }
                    )) {
                        HStack(spacing: 4) {
                            Text("Skip short transcriptions")
                            InfoTip("Automatically skip AI enhancement when the transcription has very few words. Short phrases like \"yes\", \"thank you\", or quick commands don't benefit from enhancement.")
                        }
                    }
                    .toggleStyle(.switch)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isSkipShortEnhancementEnabled && isShortEnhancementExpanded ? 90 : 0))
                        .opacity(isSkipShortEnhancementEnabled ? 1 : 0.4)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isHandlingToggleChange else { return }
                    if isSkipShortEnhancementEnabled {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShortEnhancementExpanded.toggle()
                        }
                    }
                }

                if isSkipShortEnhancementEnabled && isShortEnhancementExpanded {
                    Picker("Minimum words", selection: $shortEnhancementWordThreshold) {
                        ForEach(1...15, id: \.self) { count in
                            Text("\(count) \(count == 1 ? "word" : "words")").tag(count)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.leading, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isShortEnhancementExpanded)
        }
    }

    private var requestTimeoutSection: some View {
        sectionBlock(
            label: "REQUEST TIMEOUT",
            info: "Set how long to wait for the AI provider to respond. If no response is received within this duration, you can either fail immediately and paste the original transcription, or retry the request (up to 3 attempts)."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Timeout duration", selection: $enhancementTimeoutSeconds) {
                    ForEach([3, 5, 7, 10, 15, 20, 30, 40, 50, 60], id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
                .pickerStyle(.menu)

                Picker("On timeout", selection: $retryOnTimeout) {
                    Text("Fail immediately").tag(false)
                    Text("Retry").tag(true)
                }
                .pickerStyle(.menu)
            }
        }
    }

    @ViewBuilder
    private var onDeviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionBlock(label: "ON-DEVICE") {
                VStack(alignment: .leading, spacing: 12) {
                    // W11.B — surface the active local path. AFM is the
                    // primary path on macOS 26+ with Apple Intelligence
                    // enabled; MLX is the fallback. Informational only,
                    // no toggle.
                    HStack(spacing: 6) {
                        Image(systemName: enhancementService.activeLocalPathDescription.hasPrefix("Apple")
                              ? "applelogo"
                              : "cpu")
                            .foregroundColor(.secondary)
                        Text("Active path:")
                            .foregroundColor(.secondary)
                        Text(enhancementService.activeLocalPathDescription)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .font(.callout)

                    // W14.A — Force MLX over AFM. Visible only when `.mlx`
                    // is the active provider AND AFM is available (otherwise
                    // there's no AFM to force away from).
                    if enhancementService.aiService.selectedProvider == .mlx,
                       afmAvailable {
                        Toggle(isOn: $forceMLXOverAFM) {
                            HStack(spacing: 4) {
                                Text("Force MLX (skip AFM)")
                                InfoTip("By default, selecting MLX routes through Apple Foundation Models when available (W11.B). Turn this on to send requests directly to MLX inference, bypassing AFM. Useful if you specifically want MLX behavior or if AFM rejects your prompts too aggressively.")
                            }
                        }
                        .toggleStyle(.switch)
                    }

                    // W14.B — AFM prewarm gate. Visible whenever AFM is
                    // available so the user can disable warm() calls and
                    // empirically A/B cold-vs-warm AFM ttft.
                    if afmAvailable {
                        Toggle(isOn: $prewarmAFMEnhancement) {
                            HStack(spacing: 4) {
                                Text("Pre-warm AFM on launch / wake")
                                InfoTip("Sends a tiny dummy prompt to Apple Foundation Models on app launch and after wake-from-sleep so the first real enhancement skips the cold-load delay. Disable to A/B test cold-vs-warm AFM ttft (the metric written to enhancement-timings.csv).")
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(!UserDefaults.standard.bool(forKey: "PrewarmModelOnWake"))
                    }

                    // Idle eviction only governs the MLX in-memory model.
                    // Hidden on `.foundationModels` since MLX never loads
                    // in that path.
                    if enhancementService.aiService.selectedProvider == .mlx {
                        Picker(selection: $mlxIdleEvictSeconds) {
                            Text("60 seconds").tag(60)
                            Text("5 minutes").tag(300)
                            Text("10 minutes").tag(600)
                            Text("20 minutes").tag(1200)
                            Text("30 minutes").tag(1800)
                            Text("45 minutes").tag(2700)
                            Text("1 hour").tag(3600)
                            Text("Never").tag(Int.max)
                        } label: {
                            HStack(spacing: 4) {
                                Text("Idle eviction")
                                InfoTip("How long the MLX on-device model stays in memory after the last enhancement. Higher values trade memory for fewer cold-load spikes; lower values free memory faster. Applies on the next time the MLX provider is reloaded.")
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // W11.D — empirical timing log access. Every on-device
                    // enhancement (AFM and MLX) appends one row to the CSV
                    // under Application Support so the user can verify
                    // perf changes quantitatively.
                    HStack(spacing: 8) {
                        Button(action: openTimingsFolder) {
                            Label("Open timings folder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .help("Reveal enhancement-timings.csv in Finder")

                        Button(action: copyTimingsPath) {
                            Label(
                                didCopyTimingsPath ? "Copied!" : "Copy CSV path",
                                systemImage: didCopyTimingsPath ? "checkmark" : "doc.on.doc"
                            )
                        }
                        .buttonStyle(.bordered)
                        .help("Copy the absolute CSV path to the clipboard")
                    }
                }
            }
            sectionFooter("Each on-device enhancement appends a row to enhancement-timings.csv (timestamp, model, prompt mode, prep/ttft/gen/total seconds, gap, outcome).")
        }
    }

    private var shortcutsSection: some View {
        sectionBlock(label: "SHORTCUTS") {
            EnhancementShortcutsView()
        }
    }

    private var lastSystemPromptSection: some View {
        sectionBlock(
            label: "LAST SENT SYSTEM PROMPT",
            info: "The exact system prompt sent to the LLM on your last enhancement, including custom vocabulary and any clipboard or screen context that was attached. Useful for debugging why the model did or didn't follow an instruction."
        ) {
            LastSystemPromptViewer()
        }
    }

    // MARK: - W11.D timings actions

    private func openTimingsFolder() {
        let url = EnhancementTimingLogger.csvURL()
        // Reveal the CSV in Finder. If the file doesn't yet exist (no
        // enhancement has run since install), reveal the parent directory
        // instead so the user lands somewhere useful.
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func copyTimingsPath() {
        let url = EnhancementTimingLogger.csvURL()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        didCopyTimingsPath = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopyTimingsPath = false
        }
    }
}

// MARK: - sectionBlock / sectionFooter helpers
//
// Compact section block + footer for narrow popover surfaces. Mirrors
// `APIKeyManagementView.sectionLabel(_:count:)` vocabulary so the popover
// reads as ONE glass surface with hierarchical sections (no SettingsCard
// double-layering over the panel's `.adaptiveGlassBackground(intensity: .panel)`).
// Used in EnhancementSettingsPanel sections per W13.D plan §S2.10.

@ViewBuilder
fileprivate func sectionBlock<Content: View>(
    label: String,
    info: String? = nil,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundColor(Palette.onyxMute.opacity(0.7))
            if let info {
                InfoTip(info)
            }
            Spacer()
        }
        content()
    }
}

fileprivate func sectionFooter(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}

// MARK: - Last System Prompt Viewer
private struct LastSystemPromptViewer: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let prompt = enhancementService.lastSystemMessageSent, !prompt.isEmpty {
                ScrollView {
                    Text(prompt)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 120, maxHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Palette.hairlineSoft, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack {
                    Text("\(prompt.count) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(prompt, forType: .string)
                        withAnimation(.easeInOut(duration: 0.15)) { didCopy = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            withAnimation(.easeInOut(duration: 0.15)) { didCopy = false }
                        }
                    } label: {
                        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Text("No enhancement has run yet. Dictate something with enhancement enabled to see the resolved system prompt here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
    }
}
