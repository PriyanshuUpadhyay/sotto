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

    /// 1.4s cyan sweep L→R (transcribing). The raw duration is shared with
    /// `HaloShimmer`, which needs the period rather than the `Animation`.
    static let sweepDuration: Double = 1.4
    static let sweep: Animation = .linear(duration: sweepDuration)

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

    /// Raw enter/exit durations — shared with AppKit contexts
    /// (`NSAnimationContext`) that need the number, not the `Animation`.
    static let stateEnterDuration: Double = 0.18
    static let stateExitDuration: Double = 0.14

    /// Capsule + chip enter transition (180ms ease-out).
    static let stateEnter: Animation = .easeOut(duration: stateEnterDuration)

    /// Capsule + chip exit transition (140ms ease-in).
    static let stateExit: Animation = .easeIn(duration: stateExitDuration)

    /// Committed-state hold before fade-out (1.5s).
    static let committedHold: TimeInterval = 1.5

    /// Post-paste review-window hold: how long the recorder panel lingers on
    /// screen after a successful paste so the ReviewTray (auto-fades at 5s) is
    /// actually usable. Slightly longer than the tray's fade so the window
    /// outlives it. A new recording supersedes this immediately.
    static let reviewWindowHold: TimeInterval = 5.5

    /// Minimum `.armed` ("LISTENING") dwell before promoting to `.recording`
    /// once first audio is observed (spec §4.2 — 120ms arming hold).
    static let armingHold: TimeInterval = 0.12

    /// Committed fade-out (400ms).
    static let committedFade: Animation = .easeOut(duration: 0.4)

    // MARK: - Live transcript tape (2026-07 revamp, design-mockups/01)

    /// 200ms word entrance — fade-in + `wordRise` rise as ASR emits it.
    static let wordIn: Animation = .easeOut(duration: 0.2)

    /// Word entrance rise distance (pt).
    static let wordRise: CGFloat = 5

    /// 300ms tentative→settled ink on the newest word.
    static let wordSettle: Animation = .easeOut(duration: 0.3)

    /// 300ms conveyor slide as older words ride left under the edge mask
    /// (mockup growEase cubic-bezier(.25,.6,.3,1)).
    static let tapeSlide: Animation = .timingCurve(0.25, 0.6, 0.3, 1, duration: 0.3)

    // MARK: - Reduce Motion fallback

    /// 200ms opacity-only fade for users with Reduce Motion enabled.
    /// Every multi-second loop must degrade to this.
    static let reducedFade: Animation = .easeInOut(duration: 0.2)
}
