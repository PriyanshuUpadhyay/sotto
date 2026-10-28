import Testing
@testable import Sotto

struct AIEnhancementServiceStripPreambleTests {

    // MARK: - Unconditional meta openers strip regardless of what follows

    /// Regression: the old blanket "next line is a list" suppression let a
    /// clearly meta line survive just because the content happened to be a
    /// list — "sure," is never a legitimate dictation list lead-in.
    @Test func stripsSureHeresPreambleEvenWhenFollowedByAList() {
        let input = "Sure, here's the cleaned transcript:\n1. Auth"
        #expect(AIEnhancementService.stripPreamble(input, transcript: "one auth") == "1. Auth")
    }

    @Test func stripsOfCoursePreamble() {
        let input = "Of course! Here's the result:\nWorking late tonight."
        #expect(AIEnhancementService.stripPreamble(input, transcript: "working late tonight") == "Working late tonight.")
    }

    // MARK: - "here's"/"here is"/"here are" are ambiguous — only strip when not a list lead-in

    /// The prompt's own few-shot: a legitimate spoken list lead-in must
    /// survive untouched.
    @Test func preservesSpokenListLeadIn() {
        let input = "We need three things:\n1. Auth\n2. Logging\n3. The retry policy"
        #expect(AIEnhancementService.stripPreamble(input, transcript: "we need three things one auth two logging three the retry policy") == input)
    }

    @Test func preservesAmbiguousHereAreListLeadIn() {
        let input = "Here are three things:\n1. Auth\n2. Logging\n3. The retry policy"
        #expect(AIEnhancementService.stripPreamble(input, transcript: "here are three things one auth two logging three the retry policy") == input)
    }

    @Test func stripsHeresPreambleWhenNotFollowedByAList() {
        let input = "Here's a cleaned-up version:\n\nWorking late tonight."
        #expect(AIEnhancementService.stripPreamble(input, transcript: "working late tonight") == "Working late tonight.")
    }

    // MARK: - The speaker's own opener is content, not a preamble

    /// Regression: a dictation that opened "Okay, I need a better visual…" and
    /// had a paragraph break lost its whole first paragraph (124 words → 45).
    @Test func keepsDictatedOkayOpener() {
        let input = "Okay, I need a better visual for this theme.\n\nThen I send another message."
        #expect(AIEnhancementService.stripPreamble(input, transcript: "okay i need a better visual for this theme\n\nthen i send another message") == input)
    }

    @Test func keepsDictatedHereIsOpener() {
        let input = "Here is the problem I'm getting at.\n\nThe account choice ignores spawn rate."
        #expect(AIEnhancementService.stripPreamble(input, transcript: "here is the problem I’m getting at\n\nthe account choice ignores spawn rate") == input)
    }

    /// The speaker opening with "okay" must not shield a real preamble that
    /// only shares that one word.
    @Test func stripsOkayPreambleWhenSpeakerAlsoSaidOkay() {
        let input = "Okay, here's the cleaned transcript:\nSo we ship on Monday."
        #expect(AIEnhancementService.stripPreamble(input, transcript: "okay so we ship on monday") == "So we ship on Monday.")
    }

    // MARK: - No-ops

    @Test func singleLineOutputIsUnchanged() {
        let input = "Working late tonight."
        #expect(AIEnhancementService.stripPreamble(input, transcript: "working late tonight") == input)
    }

    @Test func unrecognizedFirstLineIsUnchanged() {
        let input = "Deploy the parser.\nThen check the logs."
        #expect(AIEnhancementService.stripPreamble(input, transcript: "deploy the parser then check the logs") == input)
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
