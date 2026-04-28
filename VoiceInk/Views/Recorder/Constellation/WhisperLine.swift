import SwiftUI
import AppKit

// MARK: - WhisperLine (legacy)
//
// Pre-W2 ambient breath line. Retained ONLY for `CinematicWalkthrough.swift`
// (onboarding, deferred per spec §5). The live recorder is invisible at idle
// per spec §3 — `ConstellationCluster` does not mount this view. Do not add
// new consumers.
//
// Whisper — ambient breath line below the notch when the recorder is idle.
// Spec §3.1 (Idle / Whisper). Visual reference:
// `.superpowers/brainstorm/22968-1777317412/content/idle-state.html`.
//
// 60×2pt rounded line. 3-stop horizontal gradient. 8pt soft glow. Breathes
// at 2.6s with `opacity 0.35 ↔ 0.85` + `scaleX 0.85 ↔ 1.0`.
//
// Cursor proximity (0…1) attenuates the final opacity — line is invisible
// when the cursor is parked far from the menu bar; full-bright when nearby.
// Reduce Motion (spec §6.4) → static at mid-opacity (`0.6 × proximity`); no
// breath, no scale.
//
// Decorative only — `accessibilityHidden(true)`. State for VoiceOver lives
// on the constellation orb / chip / card, not on this line.
//
// Two appearance variants per spec §2.3 — onyx (default) inverts to light
// when the wallpaper top strip is bright (driven by `GlassAppearanceDetector`).

struct WhisperLine: View {
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared

    /// Drives visibility. Renders only when the recorder is idle. Today
    /// `HaloPhase` lacks a dedicated `.idle` case (P1.G adds one); we treat
    /// the current "nothing happening" pair (`.hidden`, `.armed`) as idle so
    /// the line ships independent of P1.G's grammar refresh.
    let phase: HaloPhase

    /// Selects gradient + glow colors. Sourced from `GlassAppearanceDetector`.
    let appearance: GlassAppearance

    /// 0…1 attenuation from `CursorProximityMonitor`. 0 = far from menu bar
    /// (line invisible). 1 = at menu bar (line at full breath amplitude).
    let proximity: Double

    @State private var raised = false

    private static let halfPeriod: TimeInterval = 1.3     // 2.6s full sine breath
    private static let lineWidth: CGFloat = 60
    private static let lineHeight: CGFloat = 2

    /// Idle predicate. See `phase` doc.
    private var isIdle: Bool {
        phase == .hidden || phase == .armed
    }

    private var shouldBreathe: Bool {
        isIdle && !motion.reduceMotion
    }

    // MARK: - Variant tokens

    private var gradientColors: [Color] {
        switch appearance {
        case .onyx:
            // Spec §3.1: `white@0 → white@0.5 → white@0`.
            return [
                Color.white.opacity(0.0),
                Color.white.opacity(0.5),
                Color.white.opacity(0.0)
            ]
        case .light:
            // Plan §P1.H: light variant inverts to `black@0 → black@0.4 → black@0`.
            return [
                Color.black.opacity(0.0),
                Color.black.opacity(0.4),
                Color.black.opacity(0.0)
            ]
        }
    }

    private var glowColor: Color {
        switch appearance {
        case .onyx:  return Color.white.opacity(0.35)
        case .light: return Color.black.opacity(0.18)
        }
    }

    // MARK: - Resolved animation values

    /// Final opacity = breath × proximity, OR mid-opacity × proximity under
    /// Reduce Motion (spec §6.4 — "Whisper line stops breathing — fades to
    /// mid-opacity static"). Multiplying by `proximity` preserves the
    /// invisible-when-far behavior even with Reduce Motion on.
    private var resolvedOpacity: Double {
        guard isIdle else { return 0 }
        let base: Double = motion.reduceMotion
            ? 0.6
            : (raised ? 0.85 : 0.35)
        return base * proximity
    }

    /// Reduce Motion → no scale animation. Locked at 1.0 so the line keeps
    /// its full 60pt width.
    private var resolvedScaleX: CGFloat {
        guard isIdle, !motion.reduceMotion else { return 1.0 }
        return raised ? 1.0 : 0.85
    }

    var body: some View {
        RoundedRectangle(cornerRadius: Self.lineHeight / 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: Self.lineWidth, height: Self.lineHeight)
            .scaleEffect(x: resolvedScaleX, y: 1.0, anchor: .center)
            .opacity(resolvedOpacity)
            .shadow(color: glowColor, radius: 8, x: 0, y: 0)
            .animation(
                shouldBreathe
                    ? .easeInOut(duration: Self.halfPeriod).repeatForever(autoreverses: true)
                    : nil,
                value: raised
            )
            .onAppear { raised = shouldBreathe }
            .onChange(of: shouldBreathe) { _, animate in raised = animate }
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#if DEBUG
private struct WhisperLinePreview: View {
    let appearance: GlassAppearance
    let proximity: Double

    var body: some View {
        WhisperLine(phase: .hidden, appearance: appearance, proximity: proximity)
            .frame(width: 220, height: 40)
    }
}

#Preview("Onyx — proximity 0.0") {
    WhisperLinePreview(appearance: .onyx, proximity: 0.0)
        .padding(40)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Onyx — proximity 0.5") {
    WhisperLinePreview(appearance: .onyx, proximity: 0.5)
        .padding(40)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Onyx — proximity 1.0") {
    WhisperLinePreview(appearance: .onyx, proximity: 1.0)
        .padding(40)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Light — proximity 0.0") {
    WhisperLinePreview(appearance: .light, proximity: 0.0)
        .padding(40)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}

#Preview("Light — proximity 0.5") {
    WhisperLinePreview(appearance: .light, proximity: 0.5)
        .padding(40)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}

#Preview("Light — proximity 1.0") {
    WhisperLinePreview(appearance: .light, proximity: 1.0)
        .padding(40)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
