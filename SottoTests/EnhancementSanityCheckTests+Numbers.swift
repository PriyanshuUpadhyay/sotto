import Testing
import Foundation
@testable import Sotto

extension EnhancementSanityCheckTests {

    // MARK: - Numbers require exact grounding, independent of the aggregate fraction

    /// Regression: the old tokenizer dropped digits entirely, so an invented
    /// number was invisible to the guard as long as enough OTHER words were
    /// grounded (2/3 aggregate here, above the 0.6 floor). A number must now
    /// trace back exactly — "600" doesn't appear in the raw as a digit or a
    /// spoken number word — and that alone makes the whole check suspect.
    @Test func invalidNumberIsAlwaysSuspectRegardlessOfAggregateFraction() {
        let raw = "the timeout is thirty seconds the timeout is sixty seconds"
        let out = "The timeout is 600 seconds."
        let v = EnhancementSanityCheck.detect(raw: raw, output: out)
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

    /// The mandated "write numbers as numerals" transformation must still
    /// pass: "60" grounds because the raw's spoken word "sixty" has the same
    /// integer value.
    @Test func numeralMatchingRawSpokenNumberWordGrounds() {
        #expect(EnhancementSanityCheck.detect(
            raw: "the timeout is thirty seconds the timeout is sixty seconds",
            output: "The timeout is 60 seconds."
        ).isClean)
    }

    /// A single digit at a list-item position ("1.", "2)") is a structural
    /// marker, not dictated content — the guard must not demand raw grounding
    /// for it in a mandated list.
    @Test func singleDigitListMarkersAreNotJudgedAsNumbers() {
        let raw = "We need three things. First, auth. Second, logging. Third, the retry policy."
        let out = "We need three things:\n1. Auth\n2. Logging\n3. The retry policy"
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isClean)
    }

    /// Regression: excluding EVERY single-digit token (not just list markers)
    /// let a real one-digit content change slip through — "version 7" altered
    /// to "version 8" scored 2/2 (only "version"/"stable" were judged). A
    /// single digit outside a list-item position must still be judged exactly
    /// like any other number.
    @Test func singleDigitContentChangeOutsideAListIsStillSuspect() {
        let v = EnhancementSanityCheck.detect(raw: "version 7 is stable", output: "Version 8 is stable.")
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

    // MARK: - Multi-word spoken numbers compose to one value, not each word's own

    /// Regression: isolated per-word matching let "twenty five"→"25" fail
    /// (neither "twenty"=20 nor "five"=5 equals 25) while wrongly accepting
    /// "twenty five"→"20" (matches the isolated word "twenty"). The composed
    /// value of the run "twenty five" is 25 — that's what output numerals are
    /// graded against now.
    @Test func composedTwentyFiveGroundsTwentyFive() {
        #expect(EnhancementSanityCheck.detect(raw: "wait twenty five minutes", output: "Wait 25 minutes.").isClean)
    }

    @Test func composedTwentyFiveDoesNotGroundIsolatedTwenty() {
        let v = EnhancementSanityCheck.detect(raw: "wait twenty five minutes", output: "Wait 20 minutes.")
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

    /// "two hundred" composes to 200, not the isolated word "hundred" (100).
    @Test func composedTwoHundredGroundsTwoHundred() {
        #expect(EnhancementSanityCheck.detect(raw: "pay two hundred dollars", output: "Pay 200 dollars.").isClean)
    }

    @Test func composedTwoHundredDoesNotGroundIsolatedHundred() {
        let v = EnhancementSanityCheck.detect(raw: "pay two hundred dollars", output: "Pay 100 dollars.")
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

    /// "and" bridges a scale word ("hundred") to what follows within a run —
    /// "one hundred and five" composes to 105, not two separate runs {100, 5}.
    @Test func composedHundredAndFiveGroundsOneOhFive() {
        #expect(EnhancementSanityCheck.detect(raw: "pay one hundred and five dollars", output: "Pay 105 dollars.").isClean)
    }

    @Test func composedHundredAndFiveDoesNotGroundIsolatedHundred() {
        let v = EnhancementSanityCheck.detect(raw: "pay one hundred and five dollars", output: "Pay 100 dollars.")
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

    /// Chained scales: "two hundred thousand" is 200 × 1000 = 200000, not
    /// 200 + 1000 = 1200 (the bug a naive "current = max(current,1)*value;
    /// total += current" reduction produces for a SECOND scale word in the
    /// same run).
    @Test func composedTwoHundredThousandGroundsChainedScale() {
        #expect(EnhancementSanityCheck.detect(
            raw: "the fund raised two hundred thousand dollars",
            output: "The fund raised 200000 dollars."
        ).isClean)
    }

    @Test func composedTwoHundredThousandDoesNotGroundNaiveSum() {
        let v = EnhancementSanityCheck.detect(
            raw: "the fund raised two hundred thousand dollars",
            output: "The fund raised 1200 dollars."
        )
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

    /// "and" between two INDEPENDENT numbers (not bridging a scale word) must
    /// NOT merge them into one composed run — each keeps its own value.
    @Test func andBetweenIndependentNumbersDoesNotComposeThem() {
        #expect(EnhancementSanityCheck.detect(raw: "bring five and six apples", output: "Bring 5 and 6 apples.").isClean)
        let v = EnhancementSanityCheck.detect(raw: "bring five and six apples", output: "Bring 11 apples.")
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

    // MARK: - Explicit 0.6 boundary (strict <)

    /// Constructed so the arithmetic is exact and independently checkable:
    /// eligible unique output tokens are {restart, daemon, logs, widget,
    /// gizmo} — 5 total. "restart", "daemon", "logs" are raw tokens
    /// (grounded); "widget" and "gizmo" appear nowhere in the raw and are not
    /// within edit distance of any raw token (ungrounded). 3/5 = 0.6 exactly.
    /// The check is `fraction < 0.6`, so 0.6 itself must stay CLEAN.
    @Test func exactlyPointSixGroundedFractionIsClean() {
        let raw = "restart the daemon and check the logs"
        let out = "Restart daemon logs widget gizmo."
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isClean)
    }

    /// One tick below the same boundary (drop one more grounded word, add one
    /// more foreign word: eligible becomes {restart, widget, gizmo, gremlin},
    /// grounded stays {restart} = 1/4 = 0.25) must be SUSPECT — proves the
    /// 0.6 case above isn't clean merely because nothing here is ever caught.
    @Test func belowPointSixGroundedFractionIsSuspect() {
        let raw = "restart the daemon and check the logs"
        let out = "Restart widget gizmo gremlin."
        let v = EnhancementSanityCheck.detect(raw: raw, output: out)
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

    // MARK: - Pipeline Latency 09: when the enhance call is skipped

    @Test("the model call happens on a clean transcript unless the skip is on")
    func cleanTranscriptStillCallsTheModel() {
        let clean = "The timeout is 60 seconds."
        #expect(EnhancementSanityCheck.isLikelyClean(clean))
        #expect(EnhancementSanityCheck.shouldCallModel(clean, skipWhenClean: false))
        #expect(!EnhancementSanityCheck.shouldCallModel(clean, skipWhenClean: true))
    }

    @Test("a transcript that still needs work always calls the model")
    func messyTranscriptAlwaysCallsTheModel() {
        let messy = "so um the timeout is thirty seconds"
        #expect(!EnhancementSanityCheck.isLikelyClean(messy))
        #expect(EnhancementSanityCheck.shouldCallModel(messy, skipWhenClean: false))
        #expect(EnhancementSanityCheck.shouldCallModel(messy, skipWhenClean: true))
    }
}
