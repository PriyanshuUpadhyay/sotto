import SwiftUI
import AVFoundation

// MARK: - AudioTimelineView (P3.A)
//
// Compact scrubbable waveform + play/pause + time labels for the History
// detail GlassCard. Presentational: playback state lives in the parent so
// detail-level actions (re-enhance, re-transcribe, delete) operate on the
// same `Transcription` record without a second `AudioPlayerManager`.
//
// Reuses `WaveformGenerator` from `AudioPlayerView.swift` — the existing
// async PCM-buffer reader is already cache-backed; we don't reinvent it
// (plan §P3.A risk note).
//
// Scrubbing performance (reviewer focus):
//   - Drag location is cached in `scrubFraction` while the gesture is
//     active. The parent's `currentTime` is only mutated on drag end,
//     avoiding a per-tick re-render of all waveform bars.
//   - Display time during a drag uses `scrubFraction * duration` directly
//     so the playhead tracks the cursor visually without any seek IO.

struct AudioTimelineView: View {
    let audioFile: URL
    let duration: TimeInterval
    @Binding var currentTime: TimeInterval
    var isPlaying: Bool
    var onPlayPause: () -> Void
    var onSeek: (TimeInterval) -> Void

    @State private var samples: [Float] = []
    @State private var isLoadingWaveform = true
    @State private var scrubFraction: CGFloat? = nil
    @State private var hoverFraction: CGFloat? = nil

    var body: some View {
        HStack(spacing: 12) {
            playPauseButton

            timelineCanvas
                .frame(height: 36)

            Text("\(formatTime(displayCurrentTime)) / \(formatTime(duration))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .onAppear { loadSamples() }
    }

    // MARK: - Subviews

    private var playPauseButton: some View {
        Button(action: onPlayPause) {
            Circle()
                .fill(Palette.transcribe.opacity(0.16))
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(Palette.transcribe.opacity(0.32), lineWidth: 0.5)
                )
                .overlay(
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .offset(x: isPlaying ? 0 : 1)  // Optical centering for play glyph.
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }

    private var timelineCanvas: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if isLoadingWaveform {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Loading waveform…")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if samples.isEmpty {
                    Text("No audio")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                } else {
                    waveformBars(width: geo.size.width)

                    if let h = hoverFraction, scrubFraction == nil {
                        Rectangle()
                            .fill(Palette.transcribe.opacity(0.6))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                            .offset(x: h * geo.size.width)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isLoadingWaveform, !samples.isEmpty else { return }
                        scrubFraction = clamp(value.location.x / geo.size.width)
                    }
                    .onEnded { value in
                        guard !isLoadingWaveform, !samples.isEmpty else { return }
                        let frac = clamp(value.location.x / geo.size.width)
                        scrubFraction = nil
                        onSeek(duration * Double(frac))
                    }
            )
            .onContinuousHover { phase in
                guard !isLoadingWaveform, !samples.isEmpty else { return }
                if case .active(let pt) = phase {
                    hoverFraction = clamp(pt.x / geo.size.width)
                } else {
                    hoverFraction = nil
                }
            }
        }
    }

    @ViewBuilder
    private func waveformBars(width: CGFloat) -> some View {
        let played = clamp(displayCurrentTime / max(0.001, duration))
        let count = max(samples.count, 1)
        let barWidth = max((width / CGFloat(count)) - 0.5, 1)

        HStack(spacing: 0.5) {
            ForEach(0..<samples.count, id: \.self) { i in
                let frac = CGFloat(i) / CGFloat(count)
                let isPlayed = frac <= played
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                isPlayed ? Palette.transcribe : Color.primary.opacity(0.30),
                                isPlayed ? Palette.transcribe.opacity(0.7) : Color.primary.opacity(0.18)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(
                        width: barWidth,
                        height: max(CGFloat(samples[i]) * 28, 2)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - State derivations

    private var displayCurrentTime: TimeInterval {
        if let frac = scrubFraction { return duration * Double(frac) }
        return currentTime
    }

    private func clamp(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Sample loading

    private func loadSamples() {
        isLoadingWaveform = true
        let url = audioFile
        Task.detached {
            let data = await WaveformGenerator.generateWaveformSamples(from: url, sampleCount: 120)
            await MainActor.run {
                self.samples = data
                self.isLoadingWaveform = false
            }
        }
    }
}
