import SwiftUI

// MARK: - GlassSwitch
//
// Custom Toggle replacement for the Adaptive Glass surfaces (Menu Bar
// dropdown, Settings glass cards). Spec §3.2: 36×20pt capsule, 16pt knob,
// accent on. Animates with the named expand spring (`Animation.haloExpand`,
// 0.38s) — NOT `.easeInOut` (reviewer focus).
//
// Geometry:
//   Track: 36 wide × 20 tall, capsule.
//   Knob:  16pt circle, 2pt inset from each end → travel = ±8pt from center.
//
// Reduce Motion → instant snap (animation cleared).
// VoiceOver → toggle trait + on/off value.

struct GlassSwitch: View {
    @Binding var isOn: Bool
    var tint: Color = Palette.enhance

    @ObservedObject private var motion = AccessibilityMotionMonitor.shared

    private let trackWidth: CGFloat = 36
    private let trackHeight: CGFloat = 20
    private let knobSize: CGFloat = 16
    private let inset: CGFloat = 2

    /// Knob horizontal offset relative to track center.
    /// Off: knob center sits at `inset + knobSize/2` from leading → offset = -travel.
    /// On:  knob center sits at `trackWidth - inset - knobSize/2` → offset = +travel.
    private var knobOffset: CGFloat {
        let travel = (trackWidth - knobSize) / 2 - inset
        return isOn ? travel : -travel
    }

    private var trackFill: Color {
        isOn ? tint : Color.white.opacity(0.18)
    }

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(trackFill)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                )
                .shadow(
                    color: isOn ? tint.opacity(0.32) : Color.clear,
                    radius: 6,
                    y: 1
                )

            Circle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
                .frame(width: knobSize, height: knobSize)
                .offset(x: knobOffset)
        }
        .frame(width: trackWidth, height: trackHeight)
        .animation(motion.reduceMotion ? nil : .haloExpand, value: isOn)
        .contentShape(Capsule())
        .onTapGesture { isOn.toggle() }
        .accessibilityElement()
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

// MARK: - Previews

#if DEBUG
private struct GlassSwitchPreviewHarness: View {
    @State private var on: Bool = false
    @State private var off: Bool = true
    let backgroundIsLight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Text("AI ENHANCEMENT")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(backgroundIsLight ? .black.opacity(0.6) : .white.opacity(0.6))
                Spacer()
                GlassSwitch(isOn: $on)
            }
            HStack(spacing: 16) {
                Text("PAUSE MEDIA")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(backgroundIsLight ? .black.opacity(0.6) : .white.opacity(0.6))
                Spacer()
                GlassSwitch(isOn: $off)
            }
        }
        .padding(32)
        .frame(width: 300)
    }
}

#Preview("Onyx") {
    GlassSwitchPreviewHarness(backgroundIsLight: false)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Light") {
    GlassSwitchPreviewHarness(backgroundIsLight: true)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
