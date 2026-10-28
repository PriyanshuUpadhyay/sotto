import SwiftUI
import AVFoundation

func formatTime(_ time: TimeInterval) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    return String(format: "%d:%02d", minutes, seconds)
}

// MARK: - Reusable Components

private struct CircleIconButton: View {
    let icon: String
    let action: () -> Void
    var fillOpacity: Double = 0.06
    var iconFont: Font = .system(size: 14, weight: .semibold)

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.primary.opacity(fillOpacity))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .font(iconFont)
                        .foregroundStyle(.primary)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct AsyncCircleButton: View {
    let defaultIcon: String
    let isLoading: Bool
    let showSuccess: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 32, height: 32)
                .overlay(
                    Group {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else if showSuccess {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.stateCommit)
                        } else {
                            Image(systemName: defaultIcon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

private struct StatusBanner: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? Palette.stateFail : Palette.stateCommit)
            Text(message)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill((isError ? Palette.stateFail : Palette.stateCommit).opacity(0.12))
                .stroke((isError ? Palette.stateFail : Palette.stateCommit).opacity(0.28), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Banner State

private enum BannerState: Equatable {
    case retranscribeSuccess
    case reEnhanceSuccess
    case retranscribeError(String)
    case reEnhanceError(String)
}

// MARK: - AudioPlayerView

struct AudioPlayerView: View {
    /// VoiceOver labels for the transport button. Held by `A11yContractTests`.
    static let playLabel = "Play"
    static let pauseLabel = "Pause"

    let url: URL
    let transcription: Transcription?
    var onInfoTap: (() -> Void)?
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var isHovering = false
    @State private var isRetranscribing = false
    @State private var isReEnhancing = false
    @State private var bannerState: BannerState?
    @EnvironmentObject private var engine: SottoEngine
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext

    private var isOperationInProgress: Bool {
        isRetranscribing || isReEnhancing
    }

    private var transcriptionService: AudioTranscriptionService {
        AudioTranscriptionService(modelContext: modelContext, engine: engine)
    }

    var body: some View {
        VStack(spacing: 8) {
            WaveformView(
                samples: playerManager.waveformSamples,
                currentTime: playerManager.currentTime,
                duration: playerManager.duration,
                isLoading: playerManager.isLoadingWaveform,
                onSeek: { playerManager.seek(to: $0) }
            )
            .padding(.horizontal, 10)

            HStack(spacing: 8) {
                Text(formatTime(playerManager.currentTime))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    CircleIconButton(icon: "folder", action: showInFinder)
                        .help("Show in Finder")

                    Button(action: { playerManager.cyclePlaybackRate() }) {
                        Circle()
                            .fill(Color.primary.opacity(playerManager.playbackRate == 1.0 ? 0.06 : 0.14))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(playerManager.playbackRate == 1.0 ? "1×" : playerManager.playbackRate == 1.5 ? "1.5×" : "2×")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.primary)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Playback speed")

                    CircleIconButton(
                        icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                        action: { playerManager.isPlaying ? playerManager.pause() : playerManager.play() }
                    )
                    .help(playerManager.isPlaying ? Self.pauseLabel : Self.playLabel)
                    .accessibilityLabel(playerManager.isPlaying ? Self.pauseLabel : Self.playLabel)
                    .scaleEffect(isHovering ? 1.05 : 1.0)
                    .onHover { hovering in
                        // A pointer entering a 32pt circle has no momentum to
                        // carry, so no spring overshoot here.
                        withAnimation(Animation.haloPhaseCrossfade) {
                            isHovering = hovering
                        }
                    }

                    AsyncCircleButton(
                        defaultIcon: "arrow.clockwise",
                        isLoading: isRetranscribing,
                        showSuccess: bannerState == .retranscribeSuccess,
                        action: retranscribeAudio
                    )
                    .disabled(isOperationInProgress)
                    .help("Retranscribe this audio")

                    if transcription != nil {
                        AsyncCircleButton(
                            defaultIcon: "wand.and.stars",
                            isLoading: isReEnhancing,
                            showSuccess: bannerState == .reEnhanceSuccess,
                            action: reEnhanceOnly
                        )
                        .disabled(isOperationInProgress || !enhancementService.isEnhancementEnabled || !enhancementService.isConfigured)
                        .opacity(enhancementService.isEnhancementEnabled && enhancementService.isConfigured ? 1.0 : 0.4)
                        .help("Re-enhance with selected prompt")
                    }

                    if let onInfoTap {
                        CircleIconButton(icon: "info.circle", action: onInfoTap)
                            .help("View details")
                    }
                }

                Spacer()

                Text(formatTime(playerManager.duration))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .onAppear {
            playerManager.loadAudio(from: url)
        }
        .onDisappear {
            playerManager.cleanup()
        }
        .overlay(
            VStack {
                if let state = bannerState {
                    switch state {
                    case .retranscribeSuccess:
                        StatusBanner(message: "Retranscription successful", isError: false)
                    case .reEnhanceSuccess:
                        StatusBanner(message: "Re-enhancement successful", isError: false)
                    case .retranscribeError(let message):
                        StatusBanner(message: message.isEmpty ? "Retranscription failed" : message, isError: true)
                    case .reEnhanceError(let message):
                        StatusBanner(message: message.isEmpty ? "Re-enhancement failed" : message, isError: true)
                    }
                }
                Spacer()
            }
            .padding(.top, 16)
            .animation(Animation.haloExpand, value: bannerState)
        )
    }

    private func showInFinder() {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    private func showTemporaryBanner(_ state: BannerState) {
        bannerState = state
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            // Mirror the `.haloExpand` entrance instead of SwiftUI's default.
            withAnimation(Animation.haloCollapse) { bannerState = nil }
        }
    }

    private func reEnhanceOnly() {
        guard let transcription = transcription else { return }

        guard enhancementService.isEnhancementEnabled, enhancementService.isConfigured else {
            showTemporaryBanner(.reEnhanceError("AI Enhancement is not enabled or configured"))
            return
        }

        isReEnhancing = true
        bannerState = nil

        Task {
            do {
                let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(transcription.text)
                await MainActor.run {
                    transcription.enhancedText = enhancedText
                    transcription.aiEnhancementModelName = enhancementService.lastEnhancementModelUsed
                    transcription.promptName = promptName
                    transcription.enhancementDuration = enhancementDuration
                    transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                    transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                    try? modelContext.save()

                    isReEnhancing = false
                    showTemporaryBanner(.reEnhanceSuccess)
                }
            } catch {
                await MainActor.run {
                    isReEnhancing = false
                    showTemporaryBanner(.reEnhanceError(error.localizedDescription))
                }
            }
        }
    }

    private func retranscribeAudio() {
        guard let currentTranscriptionModel = engine.transcriptionModelManager.currentTranscriptionModel else {
            showTemporaryBanner(.retranscribeError("No transcription model selected"))
            return
        }

        isRetranscribing = true
        bannerState = nil

        Task {
            do {
                let _ = try await transcriptionService.retranscribeAudio(from: url, using: currentTranscriptionModel)
                await MainActor.run {
                    isRetranscribing = false
                    showTemporaryBanner(.retranscribeSuccess)
                }
            } catch {
                await MainActor.run {
                    isRetranscribing = false
                    showTemporaryBanner(.retranscribeError(error.localizedDescription))
                }
            }
        }
    }
}

