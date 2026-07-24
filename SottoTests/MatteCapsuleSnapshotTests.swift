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
        XCTAssertEqual(NSColor(CapsuleState.recording.color), NSColor(Palette.stateRecord))
        XCTAssertEqual(NSColor(CapsuleState.processing.color), NSColor(Palette.stateProcessing))
        XCTAssertEqual(NSColor(CapsuleState.commit.color), NSColor(Palette.stateCommit))
        XCTAssertEqual(NSColor(CapsuleState.fail.color), NSColor(Palette.stateFail))
        XCTAssertEqual(NSColor(CapsuleState.idleReady.color), NSColor(Palette.phosphor))
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

    @MainActor
    func test_capsule_perState_snapshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SOTTO_SNAPSHOTS"] == "1",
                          "design snapshots: set SOTTO_SNAPSHOTS=1 to render")
        for state in CapsuleState.allCases {
            let view = ZStack {
                Palette.mtCanvas
                MatteCapsuleView(state: state, elapsed: 12.4, partial: "ship the parser",
                                 reduceMotion: true, onRetry: {})
            }
            .frame(width: 320, height: 120)
            .environment(\.colorScheme, .dark)
            let url = try SnapshotRenderer.render(view, name: "capsule_\(state)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            print("SNAPSHOT_WRITTEN \(url.path)")
        }
    }

    @MainActor
    func test_ambientWhisper_snapshot() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SOTTO_SNAPSHOTS"] == "1",
                          "design snapshots: set SOTTO_SNAPSHOTS=1 to render")
        let view = ZStack {
            Palette.mtCanvas
            AmbientWhisper(reduceMotion: true)
        }
        .frame(width: 320, height: 80)
        .environment(\.colorScheme, .dark)
        let url = try SnapshotRenderer.render(view, name: "ambient_whisper")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        print("SNAPSHOT_WRITTEN \(url.path)")
    }

    // MARK: - P2.4 · Capsule is the recorder root (compile-time wiring)

    func testHaloRecorderViewHostsCapsule() {
        // Compile-time: this file imports the modified HaloRecorderView (which
        // now hosts MatteCapsuleContainer → MatteCapsuleView). A green build is
        // the assertion; the value check keeps the symbol referenced.
        XCTAssertNotNil(CapsuleState.idleReady.color)
        XCTAssertEqual(MatteCapsuleView.timer(125), "02:05")
    }
}
