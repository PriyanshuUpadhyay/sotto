import SwiftUI
import AppKit

struct EnhancementSettingsPanel: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @AppStorage("SkipShortEnhancement") private var isSkipShortEnhancementEnabled = true
    @AppStorage("ShortEnhancementWordThreshold") private var shortEnhancementWordThreshold = 3
    @AppStorage("EnhancementTimeoutSeconds") private var enhancementTimeoutSeconds = 7
    @AppStorage("EnhancementRetryOnTimeout") private var retryOnTimeout = true
    @AppStorage("MLXIdleEvictSeconds") private var mlxIdleEvictSeconds = 1800
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

            // Content
            Form {
                Section {
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
                } header: {
                    Text("Context")
                }

                Section {
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

                Section {
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
                } header: {
                    HStack(spacing: 4) {
                        Text("Request Timeout")
                        InfoTip("Set how long to wait for the AI provider to respond. If no response is received within this duration, you can either fail immediately and paste the original transcription, or retry the request (up to 3 attempts).")
                    }
                }

                if enhancementService.aiService.selectedProvider == .mlx {
                    Section {
                        Picker("Idle eviction", selection: $mlxIdleEvictSeconds) {
                            Text("60 seconds").tag(60)
                            Text("5 minutes").tag(300)
                            Text("10 minutes").tag(600)
                            Text("20 minutes").tag(1200)
                            Text("30 minutes").tag(1800)
                            Text("45 minutes").tag(2700)
                            Text("1 hour").tag(3600)
                            Text("Never").tag(Int.max)
                        }
                        .pickerStyle(.menu)

                        // W11.D — empirical timing log access. Every MLX
                        // enhancement appends one row to the CSV under
                        // Application Support so the user can verify perf
                        // changes quantitatively.
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
                    } header: {
                        HStack(spacing: 4) {
                            Text("MLX (on-device)")
                            InfoTip("How long the on-device model stays in memory after the last enhancement. Higher values trade memory for fewer cold-load spikes; lower values free memory faster. Applies on the next time the MLX provider is reloaded.")
                        }
                    } footer: {
                        Text("Each MLX enhancement appends a row to enhancement-timings.csv (timestamp, model, prompt mode, prep/ttft/gen/total seconds, gap, outcome).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    EnhancementShortcutsView()
                } header: {
                    Text("Shortcuts")
                }

                Section {
                    LastSystemPromptViewer()
                } header: {
                    HStack(spacing: 4) {
                        Text("Last Sent System Prompt")
                        InfoTip("The exact system prompt sent to the LLM on your last enhancement, including custom vocabulary and any clipboard or screen context that was attached. Useful for debugging why the model did or didn't follow an instruction.")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .tint(Palette.accent)
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
