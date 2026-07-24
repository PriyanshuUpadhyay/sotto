import XCTest
@testable import Sotto

/// Covers the cold-start prewarm fixes:
///   • Fix 3 — the recorder's "warming up" vs "transcribing" label seam.
///   • The shared `FluidAudioTranscriptionService` actor's warm-state snapshot.
///
/// The Unified load-dedup itself is NOT exercised against the real loader here:
/// `UnifiedAsrManager.loadModels()` can trigger a HuggingFace download on a host
/// without the cached model, which would make the test network-bound and prone
/// to hang in headless CI. The dedup relies on the same actor-isolated
/// task-coalescing pattern already proven by `getOrLoadModels`.
final class TranscriptionPrewarmTests: XCTestCase {

    // MARK: - Fix 3 · warming-up label

    func testProcessingLabelWarmingUp() {
        XCTAssertEqual(MatteCapsuleView.processingLabel(warming: true, enhancing: false), "warming up")
    }

    func testProcessingLabelTranscribing() {
        XCTAssertEqual(MatteCapsuleView.processingLabel(warming: false, enhancing: false), "transcribing")
    }

    func testProcessingLabelEnhancing() {
        XCTAssertEqual(MatteCapsuleView.processingLabel(warming: false, enhancing: true), "enhancing")
    }

    // MARK: - FluidAudio service warm-state

    func testFreshServiceReportsNotLoaded() async {
        let service = FluidAudioTranscriptionService()
        let loaded = await service.isModelLoaded
        XCTAssertFalse(loaded, "a freshly constructed service has no resident model")
    }
}
