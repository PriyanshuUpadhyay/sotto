import SwiftUI

// MARK: - AmbientWhisper
//
// The idle "armed" affordance (spec §3): a faint breathing phosphor hairline
// that confirms Sotto is listening at near-zero visual cost and SEEDS the
// recording capsule's bloom (continuity from idle → active).
//
// • ~116×4px, gradient transparent → phosphor → transparent.
// • Breathes opacity 0.32 ↔ 0.95 over 3.0s via `Motion.breathe(reduceMotion:)`
//   — under Reduce Motion the animation is nil, so it rests at a steady mid
//   opacity (no pulsing).
// • Dock-safe placement is owned by the host panel (`MiniRecorderPanel
//   .dockSafeCapsuleOrigin`), not this view — the whisper just draws itself.
// • Toggleable to fully invisible via the recorder-style setting (the host
//   decides whether to mount it).

struct AmbientWhisper: View {
    var reduceMotion: Bool = false

    /// Breathe envelope endpoints (spec §3).
    private let dim: Double = 0.32
    private let bright: Double = 0.95

    @State private var breathing = false

    var body: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.clear, Palette.phosphor, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 116, height: 4)
            // Steady mid-opacity when motion is suppressed; otherwise breathe.
            .opacity(reduceMotion ? (dim + bright) / 2 : (breathing ? bright : dim))
            .animation(Motion.breathe(reduceMotion: reduceMotion), value: breathing)
            .onAppear { breathing = true }
            .accessibilityLabel(StateCue.voiceOverLabel(for: .idleReady))
    }
}

#if DEBUG
#Preview("Ambient whisper") {
    ZStack {
        Palette.mtCanvas
        AmbientWhisper()
    }
    .frame(width: 320, height: 80)
    .environment(\.colorScheme, .dark)
}
#endif
