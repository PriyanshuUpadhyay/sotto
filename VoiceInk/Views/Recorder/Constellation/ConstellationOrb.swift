import SwiftUI

// MARK: - ConstellationOrb (legacy)
//
// Pre-W2 16×16pt state-driven satellite. Retained ONLY for
// `CinematicWalkthrough.swift` (onboarding, deferred per spec §5). The live
// recorder uses `RingPulseDot` inside the anchor chip. Do not add new consumers.
//
// 16×16pt state-driven satellite. One of three Constellation pieces (orb /
// chip / card) per spec §3.1. Owns the per-state fill, glow, opacity shimmer,
// pulse/breath scale, failure shake-then-amber dwell, and audio-meter
// modulation. Phase-crossfaded via `Animation.haloPhaseCrossfade` (spec §2.4).
//
// Visual source of truth: `.superpowers/brainstorm/22968-1777317412/content/state-cycle.html`
// — `.const-orb` / `.const-orb::after` for the 1.5pt white@0.25 ring at -3pt
// inset, and `.orb-rec / .orb-trans / .orb-enh / .orb-done` for the 14px+28px
// shadows.
//
// Reduce Motion (`AccessibilityMotionMonitor.shared.reduceMotion`) collapses
// every state-driven motion (pulse / breath / shimmer / shake / audio-scale)
// to a static color disc per spec §6.4.

struct ConstellationOrb: View {

    // MARK: - Inputs

    /// Drives fill color, glow, motion. Maps from engine `RecordingState`.
    let phase: HaloPhase
    /// Live mic level (0…1). Modulates orb scale during `.recording` only.
    var audioMeter: Float = 0
    /// Light vs. onyx glass — currently unused in the orb (color is state-keyed,
    /// not surface-keyed) but reserved so the Constellation API stays uniform.
    var appearance: GlassAppearance = .onyx

    // MARK: - State

    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    @State private var failureStage: FailureStage = .flash
    @State private var doneFaded: Bool = false
    @State private var shakeTrigger: Int = 0

    /// Two-part `.failed` flow: red shake → amber dwell → fade.
    /// Spec §3.1 + plan §P1.D — exact, hardcoded.
    private enum FailureStage {
        case flash    // 0.32s — red color, keyframe shake
        case dwell    // 1.2s  — amber color, no motion
        case fading   // 0.22s — opacity → 0
    }

    // MARK: - Body

    var body: some View {
        orbBody
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(phase == .hidden || phase == .armed)
            .accessibilityLabel(a11yLabel)
            .animation(.haloPhaseCrossfade, value: phase)
            .task(id: phase) {
                await runPhaseStateMachine()
            }
    }

    /// Innermost orb — circle + ring + dual glow shadows + opacity, then the
    /// motion-token modifier stack. The ring overlay is a 22×22 stroke
    /// (16 + 2×3pt outset) matching the `inset: -3px` in the mockup.
    private var orbBody: some View {
        let color = currentColor
        let base = currentBaseOpacity

        return shimmerWrapper { shimmerOpacity in
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                )
                // 14px inner + 28px outer glow per spec §3.1 + state-cycle.html
                // (e.g. `box-shadow: 0 0 14px rgba(...,0.85), 0 0 28px rgba(...,0.5)`).
                .shadow(color: color.opacity(0.85), radius: 14)
                .shadow(color: color.opacity(0.50), radius: 28)
                .opacity(base * shimmerOpacity)
        }
        // Pulse / breath are state-gated. Both apply scaleEffect; only one is
        // ever active at a time (different phases), so composition is benign.
        .haloPulse(active: phase == .recording || phase == .liveText)
        .haloBreathOrb(active: phase == .enhancing)
        // Audio modulation — separate `.scaleEffect` from `HaloShake` per the
        // plan §P1.D risks note (keyframe offset + scaleEffect collide if
        // they share a transform). Gated to `.recording` so glow doesn't
        // flicker during transcribing/enhancing (reviewer focus #2).
        .scaleEffect(audioModulationScale)
        // Shake — keyframe x-offset, separate transform from any scaleEffect
        // above. Re-fires on `shakeTrigger` increment when `.failed` enters.
        .haloShake(trigger: shakeTrigger)
    }

    /// Wraps the orb in `HaloShimmer(period: 1.4)` only during `.transcribing`,
    /// driving opacity 0.55↔1.0 over a 1.4s sine. Other phases pass shimmer=1.0.
    /// Reduce Motion → `HaloShimmer` returns `content(0.5)` → static at peak.
    @ViewBuilder
    private func shimmerWrapper<C: View>(@ViewBuilder content: @escaping (Double) -> C) -> some View {
        if phase == .transcribing {
            HaloShimmer(period: 1.4) { p in
                content(0.55 + 0.45 * sin(.pi * p))
            }
        } else {
            content(1.0)
        }
    }

    // MARK: - Derived state

    private var currentColor: Color {
        // Failure dwell swaps red → amber for 1.2s (spec §3.1, plan §P1.D).
        if phase == .failed && failureStage == .dwell {
            return Palette.warn
        }
        return phase.glowColor
    }

    /// Base orb opacity, before shimmer multiplication. `.hidden`/`.armed`
    /// are 0 (orb invisible during idle/armed); `.done`/`.failed` flip to 0
    /// at the end of their respective state machines.
    private var currentBaseOpacity: Double {
        switch phase {
        case .hidden, .armed:
            return 0
        case .done:
            return doneFaded ? 0 : 1
        case .failed:
            return failureStage == .fading ? 0 : 1
        default:
            return 1
        }
    }

    /// Audio-driven scale, gated to `.recording` and Reduce Motion off.
    /// `.scaleEffect(1.0 + audioMeter * 0.06)` per plan §P1.D.
    private var audioModulationScale: CGFloat {
        guard !motion.reduceMotion else { return 1.0 }
        guard phase == .recording || phase == .liveText else { return 1.0 }
        let clamped = min(max(audioMeter, 0), 1)
        return 1.0 + CGFloat(clamped) * 0.06
    }

    /// VoiceOver label per spec §6.4. Color word matches the visual cue so
    /// the orb is identifiable independent of color (color-blind support
    /// is supplied by chip/card icons; here the spoken color is the cue).
    private var a11yLabel: String {
        switch phase {
        case .hidden, .armed:
            return ""
        case .recording, .liveText:
            return "VoiceInk recording, red"
        case .transcribing:
            return "VoiceInk transcribing, cyan"
        case .enhancing:
            return "VoiceInk enhancing, violet"
        case .done:
            return "VoiceInk done, green"
        case .failed:
            return failureStage == .dwell
                ? "VoiceInk failed, amber"
                : "VoiceInk failed, red"
        }
    }

    // MARK: - Phase state machine
    //
    // `.task(id: phase)` cancels + restarts on phase change. Throwing
    // `Task.sleep` lets cancellation bail the whole sequence cleanly.

    @MainActor
    private func runPhaseStateMachine() async {
        switch phase {
        case .failed:
            failureStage = .flash
            shakeTrigger &+= 1
            do {
                try await Task.sleep(for: .milliseconds(320))
                withAnimation(.haloPhaseCrossfade) { failureStage = .dwell }
                try await Task.sleep(for: .milliseconds(1200))
                withAnimation(.haloPhaseCrossfade) { failureStage = .fading }
            } catch {
                // Cancelled — phase moved on, leave state to next .task pass.
            }

        case .done:
            doneFaded = false
            do {
                try await Task.sleep(for: .milliseconds(280))
                withAnimation(.haloPhaseCrossfade) { doneFaded = true }
            } catch {
                // Cancelled.
            }

        default:
            // Reset terminal-phase state when leaving them so next entry
            // starts clean.
            failureStage = .flash
            doneFaded = false
        }
    }
}

// MARK: - Preview
//
// 12s timer cycles the six visible phases (recording → transcribing →
// enhancing → done → failed → hidden) at 2s each, matching `state-cycle.html`
// row by row. Slider drives `audioMeter` to verify recording-only scale gating.

#if DEBUG
private struct ConstellationOrbPreview: View {
    @State private var index = 0
    @State private var audioMeter: Float = 0.4

    private let phases: [HaloPhase] = [
        .recording, .transcribing, .enhancing, .done, .failed, .hidden
    ]

    var body: some View {
        let phase = phases[index]
        VStack(spacing: 28) {
            Text("Phase: \(String(describing: phase))")
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.7))

            ConstellationOrb(phase: phase, audioMeter: audioMeter)
                .frame(width: 80, height: 80)

            VStack(spacing: 4) {
                Text("audioMeter: \(String(format: "%.2f", audioMeter))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.6))
                Slider(value: $audioMeter, in: 0...1)
                    .frame(width: 220)
            }
        }
        .padding(40)
        .frame(width: 320, height: 260)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                index = (index + 1) % phases.count
            }
        }
    }
}

#Preview("ConstellationOrb — phase cycle") {
    ConstellationOrbPreview()
}
#endif
