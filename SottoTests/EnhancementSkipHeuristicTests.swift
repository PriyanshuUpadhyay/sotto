import Testing
import Foundation
@testable import Sotto

/// Gate for skipping the LLM enhance step when the raw transcript is already
/// clean (punctuated, capitalized, filler-free). ~66% of AFM runs were no-ops.
struct EnhancementSkipHeuristicTests {

    @Test func cleanPunctuatedSentenceIsLikelyClean() {
        #expect(EnhancementSanityCheck.isLikelyClean("Push the changes to the branch."))
    }

    @Test func cleanQuestionIsLikelyClean() {
        #expect(EnhancementSanityCheck.isLikelyClean("Is the build passing?"))
    }

    @Test func missingTerminalPunctuationIsNotClean() {
        #expect(!EnhancementSanityCheck.isLikelyClean("Push the changes to the branch"))
    }

    @Test func lowercaseStartIsNotClean() {
        #expect(!EnhancementSanityCheck.isLikelyClean("push the changes to the branch."))
    }

    @Test func fillerUmIsNotClean() {
        #expect(!EnhancementSanityCheck.isLikelyClean("Um, push the changes to the branch."))
    }

    @Test func fillerUhIsNotClean() {
        #expect(!EnhancementSanityCheck.isLikelyClean("Push uh the changes to the branch."))
    }

    @Test func immediateDuplicateWordIsNotClean() {
        #expect(!EnhancementSanityCheck.isLikelyClean("Push the the changes to the branch."))
    }

    @Test func emptyIsNotClean() {
        #expect(!EnhancementSanityCheck.isLikelyClean(""))
        #expect(!EnhancementSanityCheck.isLikelyClean("   "))
    }

    @Test func alreadyPunctuatedRamblingIsClean() {
        // deterministicCleanup wouldn't change this — skipping a no-op LLM call
        // is the point. Acceptable to return true even though it rambles.
        let raw = "Push the changes to a single PR mentioning everything that you have done."
        #expect(EnhancementSanityCheck.isLikelyClean(raw))
    }
}
