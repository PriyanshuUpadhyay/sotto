import Testing
@testable import Sotto

struct TranscriptionTextMetricsTests {

    @Test func identicalTextHasZeroWerAndCer() {
        let rates = TranscriptionTextMetrics.errorRates(
            reference: "alpha beta",
            hypothesis: "alpha beta"
        )

        #expect(rates.wordErrorRate == 0)
        #expect(rates.characterErrorRate == 0)
    }

    @Test func oneWordSubstitutionCountsAgainstReferenceWords() {
        let wer = TranscriptionTextMetrics.wordErrorRate(
            reference: "alpha beta gamma",
            hypothesis: "alpha delta gamma"
        )

        #expect(wer == 1.0 / 3.0)
    }

    @Test func oneWordInsertionCountsAgainstReferenceWords() {
        let wer = TranscriptionTextMetrics.wordErrorRate(
            reference: "alpha beta",
            hypothesis: "alpha small beta"
        )

        #expect(wer == 0.5)
    }

    @Test func oneWordDeletionCountsAgainstReferenceWords() {
        let wer = TranscriptionTextMetrics.wordErrorRate(
            reference: "alpha beta gamma",
            hypothesis: "alpha gamma"
        )

        #expect(wer == 1.0 / 3.0)
    }

    @Test func characterErrorRateUsesCharacterLevenshteinDistance() {
        let cer = TranscriptionTextMetrics.characterErrorRate(
            reference: "kitten",
            hypothesis: "sitten"
        )

        #expect(cer == 1.0 / 6.0)
    }
}
