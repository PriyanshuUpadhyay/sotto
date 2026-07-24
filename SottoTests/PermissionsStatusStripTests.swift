import XCTest
@testable import Sotto

/// Records every interaction so a request call would be provable. The strip's
/// model is typed to the read-only `PermissionStatusReading` seam, so it can
/// only reach `refreshStatus()` — the request counters must stay zero.
final class SpyPermissionSource: PermissionStatusReading {
    let audioGranted: Bool
    let accessibilityGranted: Bool
    let screenRecordingGranted: Bool

    private(set) var refreshCount = 0
    private(set) var requestAudioCount = 0
    private(set) var requestScreenRecordingCount = 0

    init(audio: Bool, accessibility: Bool, screenRecording: Bool) {
        audioGranted = audio
        accessibilityGranted = accessibility
        screenRecordingGranted = screenRecording
    }

    func refreshStatus() { refreshCount += 1 }

    // Not part of the read-only seam — present only so the test can prove the
    // strip never reaches them. The model cannot see these through the protocol.
    func requestAudioPermission() { requestAudioCount += 1 }
    func requestScreenRecordingPermission() { requestScreenRecordingCount += 1 }
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

    // (c) The guarantee holds at the VIEW boundary: the strip is generic over the
    // read-only seam, so its `Source` cannot name a request API. Binding a
    // seam-typed spy compiles only because of that constraint, and the exact
    // path the view's `.onAppear` runs requests nothing.
    @MainActor
    func test_stripViewIsTypedToReadOnlySeam_appearPathNeverRequests() {
        let spy = SpyPermissionSource(audio: false, accessibility: true, screenRecording: false)

        let strip = PermissionsStatusStrip(source: spy)
        XCTAssertTrue(strip.source === spy, "strip binds the read-only seam spy as its source")

        // Drive the same call the view's .onAppear runs (model.onAppear()).
        PermissionsStatusStripModel(source: strip.source).onAppear()

        XCTAssertEqual(spy.refreshCount, 1, "view appear must trigger exactly one no-prompt refresh")
        XCTAssertEqual(spy.requestAudioCount, 0, "view can never request microphone access")
        XCTAssertEqual(spy.requestScreenRecordingCount, 0, "view can never request screen-recording access")
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
