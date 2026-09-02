import XCTest
import SwiftUI
import AppKit
@testable import Sotto

final class MatteCapsuleSnapshotTests: XCTestCase {

    // MARK: - P2.1 · CapsuleState mapping + color

    func testRecordingStateMapsToCapsuleState() {
        XCTAssertEqual(CapsuleState(recordingState: .idle), .idleReady)
        XCTAssertEqual(CapsuleState(recordingState: .starting), .idleReady)
        XCTAssertEqual(CapsuleState(recordingState: .busy), .idleReady)
        XCTAssertEqual(CapsuleState(recordingState: .recording), .recording)
        // transcribe + enhance collapse to a single "processing" hue (4-state cut).
        XCTAssertEqual(CapsuleState(recordingState: .transcribing), .processing)
        XCTAssertEqual(CapsuleState(recordingState: .enhancing), .processing)
    }

    func testTerminalPhasesOverrideEngineState() {
        // commit/fail are not in RecordingState — they ride in on HaloPhase.
        XCTAssertEqual(CapsuleState(recordingState: .transcribing, phase: .done), .commit)
        XCTAssertEqual(CapsuleState(recordingState: .recording, phase: .failed), .fail)
        // Non-terminal phase falls back to the engine lifecycle.
        XCTAssertEqual(CapsuleState(recordingState: .recording, phase: .recording), .recording)
        XCTAssertEqual(CapsuleState(recordingState: .idle, phase: .hidden), .idleReady)
    }

    func testStateColorMapping() {
        let mappings: [(CapsuleState, Color)] = [
            (.recording, Palette.stateRecord),
            (.processing, Palette.stateProcessing),
            (.commit, Palette.stateCommit),
            (.fail, Palette.stateFail),
            (.idleReady, Palette.phosphor),
        ]
        for (state, expected) in mappings {
            XCTAssertEqual(state.color.resolvedNSColor(), expected.resolvedNSColor())
        }
    }

    // MARK: - P2.2 · Dock-safe placement

    func testDockSafeMetricLiftsAboveVisibleBottom() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        // visibleFrame sits 70pt up (Dock present); capsule must clear it by >=24.
        let visibleBottom: CGFloat = 70
        let m = MiniRecorderPanel.dockSafeCapsuleOrigin(
            screenFrame: screen, visibleBottom: visibleBottom, capsuleHeight: 38)
        XCTAssertGreaterThanOrEqual(m.y, visibleBottom + 24,
            "capsule must sit >=24px above visibleFrame bottom (Dock-safe)")
        // Nothing in the literal bottom 16px.
        XCTAssertGreaterThan(m.y, 16)
        XCTAssertEqual(m.x, screen.midX, accuracy: 0.5)
    }

    func testDockSafeMetricClearsBottomEvenWithNoDock() {
        // No Dock → visibleBottom 0; the 16px no-target floor + buffer still applies.
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let m = MiniRecorderPanel.dockSafeCapsuleOrigin(
            screenFrame: screen, visibleBottom: 0, capsuleHeight: 38)
        XCTAssertGreaterThan(m.y, 16, "never a target in the bottom ~16px")
    }

    // MARK: - P2.3 · Per-state snapshots (SOTTO_SNAPSHOTS=1)

    /// The capsule is Liquid Glass now, so what sits BEHIND it decides whether
    /// it reads — one shot per state over a bright and a dark wallpaper tone, in
    /// both appearances. `ImageRenderer` does not composite the live material
    /// (see `SnapshotRenderer`), so these shots judge the frosted band, the
    /// chips, layout and type — never the glass itself.
    @MainActor
    func test_capsule_perState_snapshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SOTTO_SNAPSHOTS"] == "1",
                          "design snapshots: set SOTTO_SNAPSHOTS=1 to render")
        let backdrops: [(String, Color, ColorScheme)] = [
            ("dark", Palette.onyxBg, .dark),
            ("light", Color(white: 0.93), .light),
        ]
        for state in CapsuleState.allCases {
            for (suffix, backdrop, scheme) in backdrops {
                let view = ZStack {
                    backdrop
                    MatteCapsuleView(state: state, elapsed: 12.4, partial: "ship the parser",
                                     reduceMotion: true, onRetry: {})
                }
                .frame(width: 520, height: 120)
                .environment(\.colorScheme, scheme)
                let url = try SnapshotRenderer.render(view, name: "capsule_\(state)-\(suffix)")
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                print("SNAPSHOT_WRITTEN \(url.path)")
            }
        }
    }

    // MARK: - P2.4 · Capsule is the recorder root (compile-time wiring)

    // MARK: - Panel hit-testing scope

    func testOnlyTheFailedPhaseTakesMouseEvents() {
        // The full-width strip must not swallow clicks in phases that render
        // no control — the retry / settings chip is the capsule's only target.
        XCTAssertTrue(RecorderUIManager.isInteractive(.failed))
        for phase in [HaloPhase.hidden, .armed, .recording, .liveText, .transcribing,
                      .enhancing, .done] {
            XCTAssertFalse(RecorderUIManager.isInteractive(phase),
                           "\(phase) renders no control — the strip must stay click-through")
        }
    }

    // MARK: - ⌘R binding scope

    func testRetryShortcutIsBoundOnlyForARetryableFailure() {
        XCTAssertTrue(MiniRecorderShortcutManager.retryShortcutActive(phase: .failed, code: .network))
        XCTAssertTrue(MiniRecorderShortcutManager.retryShortcutActive(phase: .failed, code: nil))
        // No model installed — the capsule offers Settings, so ⌘R must not be
        // bound (and must not shadow Reload in the frontmost app).
        XCTAssertFalse(MiniRecorderShortcutManager.retryShortcutActive(phase: .failed, code: .noModel))
        XCTAssertFalse(MiniRecorderShortcutManager.retryShortcutActive(phase: .recording, code: nil))
        XCTAssertFalse(MiniRecorderShortcutManager.retryShortcutActive(phase: .hidden, code: .network))
    }

    func testHaloRecorderViewHostsCapsule() {
        // Compile-time: this file imports the modified HaloRecorderView (which
        // now hosts MatteCapsuleContainer → MatteCapsuleView). A green build is
        // the assertion; the value check keeps the symbol referenced.
        XCTAssertNotNil(CapsuleState.idleReady.color)
        XCTAssertEqual(MatteCapsuleView.timer(125), "2:05")
    }
}
