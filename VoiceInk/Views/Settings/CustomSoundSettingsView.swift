import SwiftUI
import UniformTypeIdentifiers

/// Custom Sounds settings (spec §3.10, plan P3.G).
///
/// One `GlassCard` per spec cue (start / transcribeComplete / enhanceComplete /
/// cancel / fail). Each card carries the cue's name, one-line description, a
/// 60pt waveform preview (lollipop bars sampled from the synthesized cue's PCM
/// envelope), and ▶ Play / Replace / Reset buttons.
///
/// Waveform sampling runs off-main via `CustomSoundManager.prepareWaveformPreview`;
/// the cards render a faint placeholder until samples land, then re-render
/// once the cache fills. No synchronous PCM synthesis on `onAppear`.
struct CustomSoundSettingsView: View {
    @StateObject private var customSoundManager = CustomSoundManager.shared
    @ObservedObject private var soundManager = SoundManager.shared

    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private static let waveformBins = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(CustomSoundManager.SoundType.allCases) { type in
                cueCard(for: type)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            for type in CustomSoundManager.SoundType.allCases {
                customSoundManager.prepareWaveformPreview(for: type, bins: Self.waveformBins)
            }
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Cue card

    @ViewBuilder
    private func cueCard(for type: CustomSoundManager.SoundType) -> some View {
        let isCustom = customSoundManager.isUsingCustom(for: type)
        let filename = customSoundManager.getSoundDisplayName(for: type)

        GlassCard(cornerRadius: 14, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                // Title + description + status pill
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(type.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        if isCustom {
                            Text("Custom")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.warn)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Palette.warn.opacity(0.16))
                                )
                        }

                        Spacer()

                        if let filename, isCustom {
                            Text(filename)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Text(type.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Waveform preview
                WaveformPreview(
                    samples: customSoundManager.cachedWaveformPreview(for: type) ?? [],
                    tint: tint(for: type)
                )
                .frame(height: 60)
                .frame(maxWidth: .infinity)

                // Buttons
                HStack(spacing: 8) {
                    Button {
                        soundManager.playPreview(type)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Play \(type.displayName)")

                    Button {
                        selectSound(for: type)
                    } label: {
                        Label("Replace", systemImage: "folder")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Choose a custom audio file")

                    Button {
                        customSoundManager.resetSoundToDefault(for: type)
                    } label: {
                        Label("Reset", systemImage: "arrow.uturn.backward")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isCustom)
                    .help(isCustom ? "Revert to the synthesized default" : "Already using the synthesized default")

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Per-cue tint

    /// Color-keys the waveform preview to the cue's spec tint:
    /// start → red, transcribe → cyan, enhance → violet, cancel → neutral,
    /// fail → amber. Pulled directly from the spec §2.1 palette.
    private func tint(for type: CustomSoundManager.SoundType) -> Color {
        switch type {
        case .start:              return Palette.recording
        case .transcribeComplete: return Palette.transcribe
        case .enhanceComplete:    return Palette.enhance
        case .cancel:             return Palette.neutral
        case .fail:               return Palette.warn
        }
    }

    // MARK: - File picker

    private func selectSound(for type: CustomSoundManager.SoundType) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(type.displayName) Sound"
        panel.message = "Select an audio file (≤3 seconds)"
        panel.allowedContentTypes = [
            UTType.audio,
            UTType.mp3,
            UTType.wav,
            UTType.aiff
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let result = customSoundManager.setCustomSound(url: url, for: type)
            if case .failure(let error) = result {
                alertTitle = "Invalid Audio File"
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }
}

// MARK: - Waveform preview

/// Lollipop-bar render of a downsampled cue envelope. Bars centered on the
/// horizontal axis (mirror top + bottom) so the shape reads as a stylized
/// waveform rather than a bar chart. Renders an empty placeholder when
/// `samples` is empty (cache pending).
private struct WaveformPreview: View {
    let samples: [Float]
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                // Center axis line — visible even before samples land so the
                // card holds its shape on first paint.
                Rectangle()
                    .fill(tint.opacity(0.15))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)

                if !samples.isEmpty {
                    HStack(alignment: .center, spacing: barSpacing(width: width)) {
                        ForEach(samples.indices, id: \.self) { idx in
                            let amp = CGFloat(samples[idx])
                            let barHeight = max(2, amp * (height - 4))
                            Capsule()
                                .fill(tint.opacity(0.85))
                                .frame(width: barWidth(width: width), height: barHeight)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(width: width, height: height)
        }
        .accessibilityHidden(true)
    }

    /// Bar width tuned so 48 bins fill ~80% of the available width with a
    /// visible gap. Falls back gracefully on narrow widths.
    private func barWidth(width: CGFloat) -> CGFloat {
        let count = max(1, samples.count)
        let usable = width * 0.94
        return max(1.5, (usable / CGFloat(count)) * 0.6)
    }

    private func barSpacing(width: CGFloat) -> CGFloat {
        let count = max(1, samples.count)
        let usable = width * 0.94
        return max(0.5, (usable / CGFloat(count)) * 0.4)
    }
}

#Preview {
    CustomSoundSettingsView()
        .frame(width: 460)
        .padding()
}
