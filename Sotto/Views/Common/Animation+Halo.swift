import AppKit
import SwiftUI

// MARK: - Animation+Halo
//
// Sotto's animation grammar — three sanctioned springs + one phase-crossfade,
// plus four motion-token wrappers (Shimmer, Shake, Pulse, BreathOrb). Spec §2.4.
//
// Every motion token honors `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
// via `AccessibilityMotionMonitor.shared`, which live-subscribes to
// `accessibilityDisplayOptionsDidChangeNotification` so System Settings →
// Accessibility → Display toggles propagate without an app restart
// (plan open question #4, resolved 2026-04-28).
//
// Reviewer note: every numeric in this file is a spec constant. Call sites
// must not hand-roll their own `easeInOut(duration:)` / scale / offset values —
// they should consume `Animation.halo*` or one of the four token modifiers.

extension Animation {
    /// Expand, reveal, morph-up. Spec §2.4.
    static let haloExpand = Animation.spring(response: 0.38, dampingFraction: 0.78)

    /// Contract, dismiss, morph-down. Spec §2.4.
    static let haloCollapse = Animation.spring(response: 0.42, dampingFraction: 1.00)

    /// Enhancing breath. Bind via `.animation(.haloBreathe, value: phase)` —
    /// never `withAnimation` (retain-cycle risk noted in plan §P1.B).
    static let haloBreathe = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)

    /// Card / orb content crossfade between phases — 0.22s easeInOut paired
    /// with opacity + `scale 0.96 → 1.0`. Spec §2.4.
    static let haloPhaseCrossfade = Animation.easeInOut(duration: 0.22)
}

// MARK: - AccessibilityMotionMonitor
//
// Singleton mirror of system Reduce Motion. Downstream packets (P1.D, P1.E,
// P1.F, P1.H, all of Phase 2 + 3) consume this — never read NSWorkspace
// directly so updates remain centralized and live.

final class AccessibilityMotionMonitor: ObservableObject {
    static let shared = AccessibilityMotionMonitor()

    @Published private(set) var reduceMotion: Bool

    private var observer: NSObjectProtocol?

    private init() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let next = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            guard self?.reduceMotion != next else { return }
            self?.reduceMotion = next
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

// MARK: - HaloShimmer
//
// 1.6s phase oscillator (0..1) backed by `TimelineView(.animation)`.
// Consumers drive a gradient mask offset / opacity from `phase`.
// Reduce Motion → static mid-phase, no movement.

struct HaloShimmer<Content: View>: View {
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    var period: TimeInterval = 1.6
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        if motion.reduceMotion {
            content(0.5)
        } else {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let phase = t.truncatingRemainder(dividingBy: period) / period
                content(phase)
            }
        }
    }
}

// MARK: - HaloShake
//
// Failure x-offset keyframes {-6, 6, -4, 4, -2, 0} over 0.32s. Bumping
// `trigger` re-fires the shake. Reduce Motion → no offset.

struct HaloShake: ViewModifier {
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    var trigger: Int

    private static let totalDuration: TimeInterval = 0.32
    private static let step: TimeInterval = totalDuration / 6.0

    func body(content: Content) -> some View {
        if motion.reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, x in
                view.offset(x: x)
            } keyframes: { _ in
                LinearKeyframe(-6, duration: Self.step)
                LinearKeyframe(6,  duration: Self.step)
                LinearKeyframe(-4, duration: Self.step)
                LinearKeyframe(4,  duration: Self.step)
                LinearKeyframe(-2, duration: Self.step)
                LinearKeyframe(0,  duration: Self.step)
            }
        }
    }
}

// MARK: - HaloPulse
//
// Recording-orb pulse — `scale 1.0 ↔ 1.18` across a 1.0s easeInOut cycle.
// Drives motion via `.animation(_:value:)` (never `withAnimation`, per the
// retain-cycle note in plan §P1.B). Reduce Motion / inactive → frozen at 1.0.

struct HaloPulse: ViewModifier {
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    var active: Bool = true
    @State private var raised: Bool = false

    private static let halfPeriod: TimeInterval = 0.5  // 1.0s full cycle
    private static let peak: CGFloat = 1.18

    private var shouldAnimate: Bool { active && !motion.reduceMotion }

    func body(content: Content) -> some View {
        content
            .scaleEffect(raised ? Self.peak : 1.0)
            .animation(
                shouldAnimate
                    ? .easeInOut(duration: Self.halfPeriod).repeatForever(autoreverses: true)
                    : nil,
                value: raised
            )
            .onAppear { raised = shouldAnimate }
            .onChange(of: shouldAnimate) { _, animate in raised = animate }
    }
}

// MARK: - HaloBreathOrb
//
// Enhancing-orb breath — `scale 1.0 ↔ 1.15` across a 1.6s easeInOut cycle.
// The orb-scoped variant of `.haloBreathe`. Reduce Motion / inactive → 1.0.

struct HaloBreathOrb: ViewModifier {
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    var active: Bool = true
    @State private var raised: Bool = false

    private static let halfPeriod: TimeInterval = 0.8  // 1.6s full cycle
    private static let peak: CGFloat = 1.15

    private var shouldAnimate: Bool { active && !motion.reduceMotion }

    func body(content: Content) -> some View {
        content
            .scaleEffect(raised ? Self.peak : 1.0)
            .animation(
                shouldAnimate
                    ? .easeInOut(duration: Self.halfPeriod).repeatForever(autoreverses: true)
                    : nil,
                value: raised
            )
            .onAppear { raised = shouldAnimate }
            .onChange(of: shouldAnimate) { _, animate in raised = animate }
    }
}

// MARK: - View ergonomics

extension View {
    /// Failure x-offset shake. Increment `trigger` to re-fire.
    func haloShake(trigger: Int) -> some View {
        modifier(HaloShake(trigger: trigger))
    }

    /// Recording-orb pulse — 1.0 ↔ 1.18 over 1.0s.
    func haloPulse(active: Bool = true) -> some View {
        modifier(HaloPulse(active: active))
    }

    /// Enhancing-orb breath — 1.0 ↔ 1.15 over 1.6s.
    func haloBreathOrb(active: Bool = true) -> some View {
        modifier(HaloBreathOrb(active: active))
    }
}

// MARK: - Preview — eyeball motion + Reduce Motion compliance
//
// Toggle System Settings → Accessibility → Display → Reduce Motion ON; the
// monitor will live-update without re-launching the preview, and all four
// tokens collapse to static state.

#if DEBUG
#Preview("Halo motion grammar") {
    HaloMotionPreview()
        .padding(40)
        .frame(width: 360)
}

private struct HaloMotionPreview: View {
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    @State private var shakeTrigger = 0
    @State private var crossfade = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Reduce Motion: \(motion.reduceMotion ? "ON" : "OFF")")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            HStack(spacing: 32) {
                Circle().fill(Palette.brandAcid).frame(width: 24, height: 24)
                    .haloPulse()
                Circle().fill(Palette.brandAcid).frame(width: 24, height: 24)
                    .haloBreathOrb()
            }

            HaloShimmer { phase in
                Rectangle()
                    .fill(LinearGradient(stops: [
                        .init(color: .clear,                       location: max(0, phase - 0.3)),
                        .init(color: Palette.brandAcid.a(0.7),     location: phase),
                        .init(color: .clear,                       location: min(1, phase + 0.3))
                    ], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 220, height: 24)
                    .clipShape(Capsule())
            }

            Button("Trigger shake") { shakeTrigger &+= 1 }
                .buttonStyle(.plain)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Palette.warn.a(0.16)))
                .modifier(HaloShake(trigger: shakeTrigger))

            Button("Toggle crossfade") { crossfade.toggle() }
                .buttonStyle(.plain)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(
                    Group {
                        if crossfade {
                            Text("B").transition(.opacity.combined(with: .scale(scale: 0.96)))
                        } else {
                            Text("A").transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                )
                .animation(.haloPhaseCrossfade, value: crossfade)
                .background(Capsule().stroke(Palette.neutral.a(0.4), lineWidth: 0.5))
        }
    }
}
#endif
