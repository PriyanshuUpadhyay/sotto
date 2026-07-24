import SwiftUI

/// Motion tokens for the 4 animated HUD states + the breathing whisper.
/// Every animated surface MUST route through these so Reduce Motion has a
/// single bypass (`reduceMotion ? nil : <anim>` → an instant state cut).
enum Motion {
    static let breatheDuration: Double = 3.0   // whisper idle breathe
    static let recordPulse: Double = 1.0        // recording dot pulse
    static let processSweep: Double = 1.3       // processing sweep
    static let commitHold: Double = 1.5         // commit ✓ hold→fade

    static func breathe(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: breatheDuration).repeatForever(autoreverses: true)
    }
    static func pulse(_ d: Double, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: d).repeatForever(autoreverses: true)
    }
}
