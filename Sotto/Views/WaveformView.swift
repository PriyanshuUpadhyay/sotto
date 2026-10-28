import SwiftUI

struct WaveformView: View {
    /// VoiceOver label for the scrubber. Held by `A11yContractTests`.
    static let scrubberAccessibilityLabel = "Playback position"

    let samples: [Float]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isLoading: Bool
    var onSeek: (Double) -> Void
    @State private var isHovering = false
    @State private var hoverLocation: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if isLoading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 0.5) {
                        ForEach(0..<samples.count, id: \.self) { index in
                            WaveformBar(
                                index: index,
                                sample: samples[index],
                                isPlayed: CGFloat(index) / CGFloat(samples.count) <= CGFloat(currentTime / duration),
                                totalBars: samples.count,
                                geometryWidth: geometry.size.width,
                                isHovering: isHovering,
                                hoverProgress: hoverLocation / geometry.size.width
                            )
                        }
                    }
                    .opacity(0.6)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 2)

                    if isHovering {
                        Text(formatTime(duration * Double(hoverLocation / geometry.size.width)))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(Palette.onAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Brand.tint))
                            .offset(x: max(0, min(hoverLocation - 25, geometry.size.width - 50)))
                            .offset(y: -26)

                        Rectangle()
                            .fill(Brand.tint)
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                            .offset(x: hoverLocation)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isLoading {
                            hoverLocation = value.location.x
                            onSeek(Double(value.location.x / geometry.size.width) * duration)
                        }
                    }
            )
            .onHover { hovering in
                if !isLoading {
                    withAnimation(Animation.haloPhaseCrossfade) {
                        isHovering = hovering
                    }
                }
            }
            .onContinuousHover { phase in
                if !isLoading {
                    if case .active(let location) = phase {
                        hoverLocation = location.x
                    }
                }
            }
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityLabel(Self.scrubberAccessibilityLabel)
        .accessibilityValue(formatTime(currentTime))
        .accessibilityAdjustableAction { direction in
            guard !isLoading, duration > 0 else { return }
            let step: TimeInterval = 5
            let target = currentTime + (direction == .increment ? step : -step)
            onSeek(max(0, min(duration, target)))
        }
    }
}

struct WaveformBar: View {
    let index: Int
    let sample: Float
    let isPlayed: Bool
    let totalBars: Int
    let geometryWidth: CGFloat
    let isHovering: Bool
    let hoverProgress: CGFloat
    
    private var isNearHover: Bool {
        // The bar's own centre — the previous expression was the bar WIDTH, the
        // same for every bar, so the whole waveform bulged at once.
        let barPosition = (CGFloat(index) + 0.5) * (geometryWidth / CGFloat(totalBars))
        let hoverPosition = hoverProgress * geometryWidth
        return abs(barPosition - hoverPosition) < 20
    }
    
    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        isPlayed ? Color.primary : Color.primary.opacity(0.3),
                        isPlayed ? Color.primary.opacity(0.8) : Color.primary.opacity(0.2)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(
                width: max((geometryWidth / CGFloat(totalBars)) - 0.5, 1),
                height: max(CGFloat(sample) * 24, 2)
            )
            .scaleEffect(y: isHovering && isNearHover ? 1.15 : 1.0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 15), value: isHovering && isNearHover)
    }
}
