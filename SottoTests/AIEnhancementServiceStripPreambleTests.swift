import Testing
@testable import Sotto

struct AIEnhancementServiceStripPreambleTests {

    // MARK: - Unconditional meta openers strip regardless of what follows

    /// Regression: the old blanket "next line is a list" suppression let a
    /// clearly meta line survive just because the content happened to be a
    /// list — "sure," is never a legitimate dictation list lead-in.
    @Test func stripsSureHeresPreambleEvenWhenFollowedByAList() {
        let input = "Sure, here's the cleaned transcript:\n1. Auth"
        #expect(AIEnhancementService.stripPreamble(input) == "1. Auth")
    }

    @Test func stripsOfCoursePreamble() {
        let input = "Of course! Here's the result:\nWorking late tonight."
        #expect(AIEnhancementService.stripPreamble(input) == "Working late tonight.")
    }

    // MARK: - "here's"/"here is"/"here are" are ambiguous — only strip when not a list lead-in

    /// The prompt's own few-shot: a legitimate spoken list lead-in must
    /// survive untouched.
    @Test func preservesSpokenListLeadIn() {
        let input = "We need three things:\n1. Auth\n2. Logging\n3. The retry policy"
        #expect(AIEnhancementService.stripPreamble(input) == input)
    }

    @Test func preservesAmbiguousHereAreListLeadIn() {
        let input = "Here are three things:\n1. Auth\n2. Logging\n3. The retry policy"
        #expect(AIEnhancementService.stripPreamble(input) == input)
    }

    @Test func stripsHeresPreambleWhenNotFollowedByAList() {
        let input = "Here's a cleaned-up version:\n\nWorking late tonight."
        #expect(AIEnhancementService.stripPreamble(input) == "Working late tonight.")
    }

    // MARK: - No-ops

    @Test func singleLineOutputIsUnchanged() {
        let input = "Working late tonight."
        #expect(AIEnhancementService.stripPreamble(input) == input)
    }

    @Test func unrecognizedFirstLineIsUnchanged() {
        let input = "Deploy the parser.\nThen check the logs."
        #expect(AIEnhancementService.stripPreamble(input) == input)
    }

    // MARK: - looksLikeListItem

    @Test func recognizesListMarkers() {
        #expect(AIEnhancementService.looksLikeListItem("- Auth"))
        #expect(AIEnhancementService.looksLikeListItem("* Auth"))
        #expect(AIEnhancementService.looksLikeListItem("• Auth"))
        #expect(AIEnhancementService.looksLikeListItem("1. Auth"))
        #expect(AIEnhancementService.looksLikeListItem("2) Auth"))
    }

    @Test func rejectsDividerAndPlainProse() {
        #expect(!AIEnhancementService.looksLikeListItem("---"))
        #expect(!AIEnhancementService.looksLikeListItem("Working late tonight."))
    }
}
