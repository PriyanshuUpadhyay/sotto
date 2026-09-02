import SwiftUI

// MARK: - MicLevelBars
//
// The 6-bar input-level wave from design-mockups/01 (`.wave`). This is the
// only view in the app that observes `Recorder.audioMeter`, and it is a LEAF
// on purpose: the meter republishes ~60×/s, so observing it any higher (on
// `MatteCapsuleContainer` or `HaloRecorderView`) would re-evaluate the whole
// capsule every frame — see the de-observed `recorder` note on both.

struct MicLevelBars: View {
    @ObservedObject var recorder: Recorder
    let reduceMotion: Bool

    /// Per-bar share of the level, so the six bars read as a wave rather than
    /// one block. Shape only — the height still comes from the live meter.
    private static let profile: [Double] = [0.55, 0.8, 1.0, 0.9, 0.7, 0.5]

    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 2.5
    private static let trackHeight: CGFloat = 16
    /// Floor so a silent mic still shows six bars (a "hearing nothing" readout
    /// must look different from "not rendered"), and the span above it.
    private static let barFloor: CGFloat = 4
    private static let barSpan: CGFloat = 12

    var body: some View {
        HStack(alignment: .center, spacing: Self.barSpacing) {
            ForEach(Self.profile.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Palette.inkSecondary)
                    .frame(width: Self.barWidth, height: height(at: index))
            }
        }
        .frame(height: Self.trackHeight)
        .accessibilityHidden(true)
    }

    private func height(at index: Int) -> CGFloat {
        let level = min(1, max(0, recorder.audioMeter.averagePower))
        // Reduce Motion keeps the level readout but drops the rippling
        // wave shape — every bar moves together.
        let weight = reduceMotion ? 1 : Self.profile[index]
        return Self.barFloor + Self.barSpan * CGFloat(level * weight)
    }
}
