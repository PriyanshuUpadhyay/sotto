import Testing
@testable import Sotto

@Suite struct AcousticVocabularyServiceTests {

    @Test("term above threshold is kept, lowercased")
    func keepsAboveThreshold() {
        let out = confirmedTermSet(detections: [("Claude", -2.0)], scoreThreshold: -15.0)
        #expect(out == ["claude"])
    }

    @Test("term below threshold is dropped")
    func dropsBelowThreshold() {
        let out = confirmedTermSet(detections: [("claude", -20.0)], scoreThreshold: -15.0)
        #expect(out.isEmpty)
    }

    @Test("threshold boundary (== threshold) is kept")
    func keepsAtBoundary() {
        let out = confirmedTermSet(detections: [("cmux", -15.0)], scoreThreshold: -15.0)
        #expect(out == ["cmux"])
    }

    @Test("multiple detections of one term keep it once (best score wins)")
    func keepsBestScoreOnce() {
        let out = confirmedTermSet(
            detections: [("cmux", -18.0), ("Cmux", -3.0)],
            scoreThreshold: -15.0
        )
        #expect(out == ["cmux"])
    }

    @Test("empty detections → empty set")
    func emptyDetections() {
        let out = confirmedTermSet(detections: [], scoreThreshold: -15.0)
        #expect(out.isEmpty)
    }

    // ── acousticDetails: surfaces below-threshold (rejected) detections ────────

    @Test("acousticDetails marks a below-threshold term kept=false")
    func detailsRejectsBelowThreshold() {
        let out = acousticDetails(detections: [("claude", -20.0)], scoreThreshold: -15.0)
        #expect(out.count == 1)
        #expect(out[0].term == "claude")
        #expect(out[0].kept == false)
    }

    @Test("acousticDetails marks an above-threshold term kept=true")
    func detailsKeepsAboveThreshold() {
        let out = acousticDetails(detections: [("Claude", -2.0)], scoreThreshold: -15.0)
        #expect(out.count == 1)
        #expect(out[0].term == "claude")
        #expect(out[0].kept == true)
    }
}
