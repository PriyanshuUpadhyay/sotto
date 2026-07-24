import XCTest
@testable import Sotto

/// Guided model setup (Wave 4 Bet D) — the pure auto-select decision that
/// powers "download → activate" without hijacking a working model.
final class GuidedModelSetupTests: XCTestCase {

    // MARK: - Auto-select into an empty/broken selection

    func test_autoSelect_activatesDownloaded_whenCurrentIsNil() {
        let pick = TranscriptionModelManager.shouldAutoSelect(
            currentName: nil,
            currentUsable: false,
            downloadedName: "ggml-large-v3-turbo",
            usableNames: ["ggml-large-v3-turbo"]
        )
        XCTAssertEqual(pick, "ggml-large-v3-turbo")
    }

    func test_autoSelect_activatesDownloaded_whenCurrentSelectedButUnusable() {
        // Current model is selected (name set) but not usable (not downloaded).
        let pick = TranscriptionModelManager.shouldAutoSelect(
            currentName: "ggml-large-v3-turbo-q5_0",
            currentUsable: false,
            downloadedName: "parakeet-tdt-0.6b-v3",
            usableNames: ["parakeet-tdt-0.6b-v3"]
        )
        XCTAssertEqual(pick, "parakeet-tdt-0.6b-v3")
    }

    // MARK: - Never hijack a working setup (load-bearing guard)

    func test_autoSelect_leavesUsableCurrentUntouched() {
        let pick = TranscriptionModelManager.shouldAutoSelect(
            currentName: "ggml-large-v3-turbo",
            currentUsable: true,
            downloadedName: "parakeet-tdt-0.6b-v3",
            usableNames: ["ggml-large-v3-turbo", "parakeet-tdt-0.6b-v3"]
        )
        XCTAssertNil(pick)
    }

    // MARK: - Defensive cases

    func test_autoSelect_nil_whenDownloadedNotYetUsable() {
        // refresh hasn't surfaced the downloaded model as usable → no-op.
        let pick = TranscriptionModelManager.shouldAutoSelect(
            currentName: nil,
            currentUsable: false,
            downloadedName: "parakeet-tdt-0.6b-v3",
            usableNames: ["ggml-large-v3-turbo"]
        )
        XCTAssertNil(pick)
    }

    func test_autoSelect_nil_whenUsableNamesEmpty() {
        let pick = TranscriptionModelManager.shouldAutoSelect(
            currentName: nil,
            currentUsable: false,
            downloadedName: "parakeet-tdt-0.6b-v3",
            usableNames: []
        )
        XCTAssertNil(pick)
    }
}
