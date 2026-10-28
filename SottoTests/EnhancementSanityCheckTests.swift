import Testing
import Foundation
@testable import Sotto

struct EnhancementSanityCheckTests {

    // MARK: detect — an empty output is total loss, not a clean pass

    /// Regression: two production calls on 2026-09-16 returned "" with
    /// `outcome=success`, and the empty string was pasted over the dictation.
    /// `detect` had treated an empty output as `.clean`, so the repair ladder
    /// never ran.
    @Test func flagsEmptyOutputAsSuspect() {
        #expect(EnhancementSanityCheck.detect(raw: "Let's see how it works.", output: "").isSuspect)
        #expect(EnhancementSanityCheck.detect(raw: "Let's see how it works.", output: "   \n ").isSuspect)
    }

    /// Empty input stays clean — there is nothing to lose.
    @Test func emptyInputStaysClean() {
        #expect(EnhancementSanityCheck.detect(raw: "", output: "").isClean)
        #expect(EnhancementSanityCheck.detect(raw: "  ", output: "anything").isClean)
    }

    // MARK: detect — known answer-vs-rewrite failures must be flagged

    @Test func flagsAnswerOpenerAndPersonFlip_813() {
        let raw = "Tell me one thing. If I want to filter agents working in a particular directory, can I do that? Also are the issues scoped to a particular repo if I want to filter them or attach them directly and so on."
        let out = "Yes, you can filter agents working in a particular directory. The issues are also scoped to a particular repository, allowing you to filter them or attach them directly to that repository."
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isSuspect)
    }

    @Test func flagsPersonFlip_818() {
        let raw = "So if I want to run two cloud agents in two different directories I'll have to spawn two different Kanban dashboards. Or can I just do a single one and ask it to run another agent"
        let out = "If you want to run two cloud agents in two different directories, you'll need to spawn two different Kanban dashboards. Alternatively, you can do a single one and ask it to run another agent."
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isSuspect)
    }

    @Test func flagsPersonFlip_819() {
        let raw = "If I want to use a particular skill inside the dashboard, can I use that? For example I have a skill cord slash machine. Would I be able to use it directly?"
        let out = "If you want to use a particular skill inside the dashboard, you can. For example, if you have a skill called \"cord slash machine,\" you would be able to use it directly."
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isSuspect)
    }

    @Test func flagsReinterpretation_820() {
        let raw = "Alright, look at the logs that have been collected during the transcriptions runs that I have been doing. It seems like there are output quality issues where the model is eager to answer the questions directly rather than rewriting it and look for any other issues related to timing or any output and input quality that I've been fucking up then we can do it. Then we can do something about it."
        let out = "Alright, let's analyze the logs from the transcriptions runs to identify any output quality issues. It seems like there might be a problem with the model's eagerness to provide direct answers rather than considering alternative responses. Additionally, there could be timing issues or problems with the input and output quality that need to be addressed. Once we identify these issues, we can work on resolving them to improve the model's performance."
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isSuspect)
    }

    @Test func flagsSentenceOmission_803() {
        let raw = "What kind of data is it requesting? Can you check if the parents that we are getting are in terms of count of days or is it actual date time that is presenting the parents that is being blocked?"
        let out = "Can you check if the parents that we are getting are in terms of count of days or is it actual date time that is presenting the parents that is being blocked?"
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isSuspect)
    }

    @Test func flagsMetaPreamble_giveReasoning() {
        let raw = "Give reasoning and then reply."
        let out = "Reasoning: The request asks for a response after providing a reason, but the content within the transcript is minimal and lacks specific details or context for a meaningful response."
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isSuspect)
    }

    @Test func flagsMetaPreamble_theRequest() {
        #expect(EnhancementSanityCheck.detect(
            raw: "Fix the bug in the parser.",
            output: "The request is unclear; please provide more details about the parser."
        ).isSuspect)
    }

    @Test func flagsMetaPreamble_basedOn() {
        #expect(EnhancementSanityCheck.detect(
            raw: "Summarize the meeting notes.",
            output: "Based on the transcript, here is a concise summary of the discussion points."
        ).isSuspect)
    }

    @Test func flagsMetaPreamble_asAnAI() {
        #expect(EnhancementSanityCheck.detect(
            raw: "Tell me a joke about cats.",
            output: "As an AI, I cannot have preferences, but here is a cat joke for you."
        ).isSuspect)
    }

    // MARK: detect — known-good cleanups must NOT be flagged

    @Test func passesGoodCleanup_745() {
        let raw = "Working late. Might not be able to come to the office tomorrow but we'll try."
        let out = "Working late. Might not be able to come to the office tomorrow, but we'll try."
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isClean)
    }

    @Test func passesGoodCleanup_762() {
        let raw = "Can you fetch the origin the branch this current branch was merged into stack 01? Can you verify if those changes landed there or not?"
        let out = "Can you fetch the origin of the branch that this current branch was merged into, stack 01? Can you verify if those changes landed there or not?"
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isClean)
    }

    @Test func passesEmptyInput() {
        #expect(EnhancementSanityCheck.detect(raw: "", output: "").isClean)
        #expect(EnhancementSanityCheck.detect(raw: "   ", output: "anything").isClean)
    }

    // MARK: detect — short-utterance derailment guard (grounded-fraction)

    /// A short technical utterance whose output is unrelated must be flagged —
    /// none of the output's content words trace back to the input.
    @Test func flagsShortUtteranceDerailment() {
        let v = EnhancementSanityCheck.detect(raw: "restart the daemon", output: "The weather is nice today.")
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

    @Test func flagsShortUtteranceUnrelatedAnswer() {
        // "yes" is also an answer opener, but grounding is what catches the
        // completely foreign body here.
        let v = EnhancementSanityCheck.detect(raw: "deploy the parser", output: "Sounds like a great plan.")
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

    /// Answer-shaped derailment: the model *did the thing* and reported back
    /// instead of cleaning. "restarted" is a morph the cleanup must not make, so
    /// it is ungrounded; with "the"/"is" excluded the score is exactly 0.5 and
    /// the inclusive boundary flags it.
    @Test func flagsShortUtteranceAnswerShapedRewrite() {
        let v = EnhancementSanityCheck.detect(raw: "restart the daemon", output: "The daemon is restarted.")
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

    /// The opposite direction: a short, disfluent utterance given an aggressive
    /// but legitimate cleanup must stay clean — the surviving words are all
    /// grounded in the input, only fillers were dropped.
    @Test func passesShortDisfluentAggressiveCleanup() {
        #expect(EnhancementSanityCheck.detect(
            raw: "um yeah so uh it's done I think",
            output: "It's done, I think."
        ).isClean)
    }

    @Test func passesShortContractionAndSplitCleanup() {
        // login→"log in", cant→"can't" survive the substring grounding check.
        #expect(EnhancementSanityCheck.detect(
            raw: "cant login",
            output: "I can't log in."
        ).isClean)
    }

    // MARK: deterministicCleanup

    @Test func deterministicTrimsAndCapitalizes() {
        #expect(EnhancementSanityCheck.deterministicCleanup("  hello world  ") == "Hello world.")
    }

    @Test func deterministicRemovesFillers() {
        let out = EnhancementSanityCheck.deterministicCleanup("um so uh push the changes")
        #expect(out == "So push the changes.")
    }

    @Test func deterministicCollapsesImmediateDuplicateWords() {
        let out = EnhancementSanityCheck.deterministicCleanup("we we should ship it")
        #expect(out == "We should ship it.")
    }

    @Test func deterministicKeepsExistingTerminalPunctuation() {
        #expect(EnhancementSanityCheck.deterministicCleanup("is it working?") == "Is it working?")
    }

    @Test func deterministicEmptyStaysEmpty() {
        #expect(EnhancementSanityCheck.deterministicCleanup("   ") == "")
    }

    // MARK: detect — prompt-sanctioned formatting must survive the guard

    @Test func acceptsBulletedListFormatting() {
        let raw = "We need three things. First, auth. Second, logging. Third, the retry policy."
        let out = "We need three things:\n- Auth\n- Logging\n- The retry policy"
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isClean)
    }

    @Test func acceptsNumberedListFormatting() {
        let raw = "We need three things. First, auth. Second, logging. Third, the retry policy."
        let out = "We need three things:\n1. Auth\n2. Logging\n3. The retry policy"
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isClean)
    }

    @Test func acceptsExplicitCountListFormatting() {
        let raw = "I need four things milk eggs bread and butter"
        let out = "I need four things:\n1. Milk\n2. Eggs\n3. Bread\n4. Butter"
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isClean)
    }

    @Test func acceptsNewParagraphCue() {
        let raw = "That's the summary. New paragraph. Next, let's talk about pricing."
        let out = "That's the summary.\n\nNext, let's talk about pricing."
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isClean)
    }

    /// Line breaks that do NOT open a list item must not be credited as
    /// sentences — otherwise an output that drops half the content while adding
    /// newlines slips past `sentenceDrop`.
    @Test func flagsOmissionHiddenBehindPlainLineBreaks() {
        let raw = "The migration script rewrites every historical transcription row. It works. I checked. The changelog still needs a paragraph about the new enhancement register. Priya said she would review the pull request tomorrow morning. Good."
        let out = "The migration script rewrites\nevery historical transcription row\n\nThe changelog still needs a paragraph\nabout the new enhancement register\n\nPriya said she would review\nthe pull request tomorrow morning"
        // Every surviving word is verbatim from the raw, so grounded fraction
        // is 1.0 — sentenceDrop is the only reason left to catch the three
        // dropped sentences.
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out) == .suspect([.sentenceDrop]))
    }

    /// A list marker only counts with a following space: dividers ("---") and
    /// dash-prefixed prose must not be credited as sentence boundaries.
    @Test func flagsOmissionBehindDividersAndDashPrefixedProse() {
        let raw = "The migration script rewrites every historical transcription row. It works. I checked. The changelog still needs a paragraph about the new enhancement register. Priya said she would review the pull request tomorrow morning. Good."
        let out = "The migration script rewrites every historical transcription row\n---\n-The changelog still needs a paragraph about the new enhancement register\n-Priya said she would review the pull request tomorrow morning"
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out) == .suspect([.sentenceDrop]))
    }
}
