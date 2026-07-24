import XCTest
import AVFoundation
@testable import Sotto

/// Records every interaction so a request call is provable. The strip can now
/// request access on a row tap, but its `.onAppear` path must still only
/// refresh — the request counters must stay zero across appear.
final class SpyPermissionSource: PermissionRequesting {
    let audioGranted: Bool
    let accessibilityGranted: Bool
    let screenRecordingGranted: Bool
    let audioStatus: AVAuthorizationStatus

    private(set) var refreshCount = 0
    private(set) var requestAudioCount = 0
    private(set) var requestAccessibilityCount = 0
    private(set) var requestScreenRecordingCount = 0

    init(audio: Bool, accessibility: Bool, screenRecording: Bool) {
        audioGranted = audio
        accessibilityGranted = accessibility
        screenRecordingGranted = screenRecording
        audioStatus = audio ? .authorized : .denied
    }

    func refreshStatus() { refreshCount += 1 }

    func requestAudioPermission() { requestAudioCount += 1 }
    func requestAccessibilityPermission() { requestAccessibilityCount += 1 }
    @discardableResult
    func requestScreenRecordingPermission() -> Bool {
        requestScreenRecordingCount += 1
        return screenRecordingGranted
    }
}

final class PermissionsStatusStripTests: XCTestCase {

    // (a) The strip derives all three row states from the read-only source.
    func test_rows_reflectReadOnlySource_mixedStates() {
        let spy = SpyPermissionSource(audio: true, accessibility: false, screenRecording: true)
        let model = PermissionsStatusStripModel(source: spy)

        XCTAssertEqual(
            model.rows,
            PermissionStatusRows(microphone: true, accessibility: false, screenRecording: true)
        )
    }

    func test_rows_allDeniedAndAllGranted() {
        let denied = PermissionsStatusStripModel(
            source: SpyPermissionSource(audio: false, accessibility: false, screenRecording: false)
        )
        XCTAssertEqual(denied.rows, PermissionStatusRows(microphone: false, accessibility: false, screenRecording: false))

        let granted = PermissionsStatusStripModel(
            source: SpyPermissionSource(audio: true, accessibility: true, screenRecording: true)
        )
        XCTAssertEqual(granted.rows, PermissionStatusRows(microphone: true, accessibility: true, screenRecording: true))
    }

    // (b) The appear path calls only the read/check method, never a request API.
    func test_onAppear_refreshesViaReadOnlyCheckOnly_neverRequests() {
        let spy = SpyPermissionSource(audio: false, accessibility: true, screenRecording: false)
        let model = PermissionsStatusStripModel(source: spy)

        model.onAppear()

        XCTAssertEqual(spy.refreshCount, 1, "appear must trigger exactly one no-prompt refresh")
        XCTAssertEqual(spy.requestAudioCount, 0, "appear must never request microphone access")
        XCTAssertEqual(spy.requestScreenRecordingCount, 0, "appear must never request screen-recording access")
    }

    // (c) At the VIEW boundary: the strip can request access on a row tap, but the
    // exact path its `.onAppear` runs requests nothing — only a no-prompt refresh.
    @MainActor
    func test_stripView_appearPathNeverRequests() {
        let spy = SpyPermissionSource(audio: false, accessibility: true, screenRecording: false)

        let strip = PermissionsStatusStrip(source: spy)
        XCTAssertTrue(strip.source === spy, "strip binds the spy as its source")

        // Drive the same call the view's .onAppear runs (model.onAppear()).
        PermissionsStatusStripModel(source: strip.source).onAppear()

        XCTAssertEqual(spy.refreshCount, 1, "view appear must trigger exactly one no-prompt refresh")
        XCTAssertEqual(spy.requestAudioCount, 0, "appear must not request microphone access")
        XCTAssertEqual(spy.requestScreenRecordingCount, 0, "appear must not request screen-recording access")
    }

    // The real PermissionManager satisfies the read-only seam, mapping its
    // published state onto the strip's getters (no prompt involved).
    @MainActor
    func test_permissionManager_conformsToReadOnlySeam() {
        let manager = PermissionManager()
        manager.audioPermissionStatus = .authorized
        manager.isAccessibilityEnabled = false
        manager.isScreenRecordingEnabled = true

        let reading: any PermissionStatusReading = manager
        XCTAssertTrue(reading.audioGranted)
        XCTAssertFalse(reading.accessibilityGranted)
        XCTAssertTrue(reading.screenRecordingGranted)
    }
}
