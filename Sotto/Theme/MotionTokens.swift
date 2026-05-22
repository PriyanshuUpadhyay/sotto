import SwiftUI

// MARK: - MotionTokens
//
// Pure value types. NO model-layer imports. Source of truth: spec §4.3.
// Each token = (duration, easing, repeatStyle). Caller composes via
// `.repeatForever(autoreverses:)` / `.delay(_:)` as needed.
//
// File location note: this file lives under `Sotto/Theme/` as the foundation
// for the post-rename `Sotto` module tree. The foundation milestone (m02)
// stages tokens here so the SETTINGS / MAIN pairs in m03 can consume them
// once the Xcode project is updated to include `Sotto/` as a synchronized
// source root. HUD callers in m02 reference the values inline (palette
// + animation literals already in `HaloMaterial` / `MotionTokens`'s consumers)
// to avoid touching `*.xcodeproj/project.pbxproj` (forbidden under m02).

enum MotionTokens {

    /// 1.0s red dot pulse (recording).
    static let pulse: Animation = .easeInOut(duration: 1.0)

    /// 0.8–1.1s staggered bar bounce (recording audio bars).
    /// Caller selects per-bar duration in `[0.8, 1.1]` and `.delay(_:)` offsets
    /// for the staggered effect.
    static let barsRangeMin: Double = 0.8
    static let barsRangeMax: Double = 1.1

    /// 1.4s cyan sweep L→R (transcribing).
    static let sweep: Animation = .linear(duration: 1.4)

    /// 1.6s violet halo breath (enhancing).
    static let breathe: Animation = .easeInOut(duration: 1.6)

    /// 1.2s arming border breathe.
    static let arming: Animation = .easeInOut(duration: 1.2)

    /// 0.8s red error blink (fail).
    static let blink: Animation = .easeInOut(duration: 0.8)

    /// 200ms dot bounce (transcribing menubar fallback; HUD does not use).
    static let dotJump: Animation = .easeOut(duration: 0.2)

    /// 1.6s violet arc spin (enhancing menubar; HUD does not use).
    static let spin: Animation = .linear(duration: 1.6)

    // MARK: - Cross-state durations

    /// Capsule + chip enter transition (180ms ease-out).
    static let stateEnter: Animation = .easeOut(duration: 0.18)

    /// Capsule + chip exit transition (140ms ease-in).
    static let stateExit: Animation = .easeIn(duration: 0.14)

    /// Committed-state hold before fade-out (1.5s).
    static let committedHold: TimeInterval = 1.5

    /// Minimum `.armed` ("LISTENING") dwell before promoting to `.recording`
    /// once first audio is observed (spec §4.2 — 120ms arming hold).
    static let armingHold: TimeInterval = 0.12

    /// Committed fade-out (400ms).
    static let committedFade: Animation = .easeOut(duration: 0.4)

    // MARK: - Reduce Motion fallback

    /// 200ms opacity-only fade for users with Reduce Motion enabled.
    /// Every multi-second loop must degrade to this.
    static let reducedFade: Animation = .easeInOut(duration: 0.2)
}
