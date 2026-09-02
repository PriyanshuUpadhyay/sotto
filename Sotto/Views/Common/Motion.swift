import SwiftUI

/// The Reduce Motion WRAPPER over `MotionTokens` — every animated surface
/// routes through it so Reduce Motion has a single bypass
/// (`reduceMotion ? nil : <anim>` → an instant state cut).
///
/// The durations below are references, never second copies: `MotionTokens`
/// (spec §4.3) is the source of truth, so a timing cannot silently drift
/// between the capsule and the tray.
enum Motion {
    static let breatheDuration: Double = MotionTokens.breatheDuration
    static let recordPulse: Double = MotionTokens.pulseDuration
    static let processSweep: Double = MotionTokens.sweepDuration
    static let commitHold: Double = MotionTokens.committedHold

    static func breathe(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: breatheDuration).repeatForever(autoreverses: true)
    }
    static func pulse(_ d: Double, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: d).repeatForever(autoreverses: true)
    }
}
