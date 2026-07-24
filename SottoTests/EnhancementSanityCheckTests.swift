import Testing
import Foundation
@testable import Sotto

struct EnhancementSanityCheckTests {

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

    // MARK: - Replay table: every prompt few-shot, good output clean / plausible bad output suspect

    struct FewShot: Sendable {
        let name: String
        let raw: String
        let good: String
        let bad: String
    }

    /// One entry per `AIPrompts.customPromptTemplate` few-shot example, plus a
    /// plausible bad output for the SAME raw input covering the failure
    /// categories the guard must still catch (answer, meta, person-flip,
    /// hallucinated content) even after the prompt was un-weakened to mandate
    /// self-correction collapse / filler removal / run-on splitting.
    private static let fewShots: [FewShot] = [
        FewShot(
            name: "filterAgents",
            raw: "so um if I want to filter the agents like can I do that",
            good: "So if I want to filter the agents, can I do that?",
            bad: "Yes, you can filter the agents."
        ),
        FewShot(
            name: "checkLogs",
            raw: "look at the logs and uh figure out whats going wrong then we can fix it",
            good: "Look at the logs and figure out what's going wrong, then we can fix it.",
            bad: "The transcript asks to review logs and diagnose issues."
        ),
        FewShot(
            name: "useSkillDirectly",
            raw: "tell me one thing would I be able to use the skill directly you know",
            good: "Tell me one thing — would I be able to use the skill directly?",
            bad: "Yes, you can use the skill directly."
        ),
        FewShot(
            name: "selfCorrectionShipDate",
            raw: "lets ship it on friday scratch that lets ship it on monday",
            good: "Let's ship it on Monday.",
            bad: "Let's ship it on Friday and notify the whole team."
        ),
        FewShot(
            name: "repeatedRestatementTimeout",
            raw: "the timeout is thirty seconds the timeout is sixty seconds",
            good: "The timeout is 60 seconds.",
            bad: "The timeout is 60 seconds due to network latency issues."
        ),
        FewShot(
            name: "spokenList",
            raw: "we need three things first auth second logging third the retry policy",
            good: "We need three things:\n1. Auth\n2. Logging\n3. The retry policy",
            bad: "Based on the transcript, three things are needed: auth, logging, and the retry policy."
        ),
        FewShot(
            name: "newParagraphCue",
            raw: "thats the summary new paragraph next lets talk about pricing",
            good: "That's the summary.\n\nNext, let's talk about pricing.",
            bad: "The summary is complete. Let's schedule a meeting to discuss the budget and timeline next quarter."
        ),
        FewShot(
            name: "camelCaseIdentifier",
            raw: "the function is called get user profile camel case in auth service dot swift",
            good: "The function is called getUserProfile in AuthService.swift.",
            bad: "I recommend calling it getUserProfile inside AuthService.swift."
        ),
    ]

    @Test(arguments: fewShots) func fewShotGoodOutputPassesGuard(_ shot: FewShot) {
        #expect(EnhancementSanityCheck.detect(raw: shot.raw, output: shot.good).isClean, "\(shot.name) good output should be clean")
    }

    @Test(arguments: fewShots) func fewShotBadOutputFailsGuard(_ shot: FewShot) {
        #expect(EnhancementSanityCheck.detect(raw: shot.raw, output: shot.bad).isSuspect, "\(shot.name) bad output should be suspect")
    }

    // MARK: - Grounding arm (b): active custom vocabulary

    /// Two-eligible-token utterance where the correction is a pure vocabulary
    /// swap: without the vocabulary set it grounds at 0.5 (below the 0.6
    /// floor) and is flagged; with the word in the active custom vocabulary,
    /// it grounds at 1.0.
    @Test func vocabularyGroundsAMandatedTermCorrection() {
        let raw = "deploy cooper netties"
        let out = "Deploy Kubernetes."
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isSuspect)
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out, vocabulary: ["kubernetes"]).isClean)
    }

    // MARK: - sentenceDrop must not fire on a mandated, punctuated self-correction collapse

    /// Regression: a PUNCTUATED raw ("Ship Friday. Scratch that. Ship Monday.")
    /// has 3 sentences; the mandated collapse to "Ship Monday." has 1 — a bare
    /// sentence-count ratio (1/3) would trip sentenceDrop despite grounding at
    /// 1.0. The un-punctuated few-shot ("lets ship it on friday scratch that
    /// lets ship it on monday") never exercised this because raw with no
    /// punctuation counts as a single sentence.
    @Test func selfCorrectionCollapseWithPunctuatedRawDoesNotTripSentenceDrop() {
        let raw = "Ship Friday. Scratch that. Ship Monday."
        let out = "Ship Monday."
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isClean)
    }

    /// The exemption is narrow: a cue word present near an UNRELATED real
    /// omission must not launder it — grounding stays low because the
    /// surviving words don't trace back to the raw, so sentenceDrop (and
    /// lowGroundedFraction) still fire.
    @Test func selfCorrectionCueDoesNotLaunderARealOmission() {
        let raw = "Deploy the parser. Actually, also update the changelog. Then notify the team."
        let out = "Something else entirely unrelated happened here today."
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isSuspect)
    }

    /// The GROUNDED-subset reverse hole: the omitted sentence's content is
    /// unrelated to the correction but the SURVIVING output is still fully
    /// grounded (unlike the test above, which used unrelated prose that fails
    /// on grounding alone). "Actually deploy the parser" carries real content
    /// beyond the cue, so it still counts toward the raw denominator — only
    /// "Test the parser" (the immediately preceding, superseded sentence) is
    /// discounted. Dropping "Update docs." on top of that must still trip
    /// sentenceDrop (2 effective raw sentences, 1 output sentence = 0.5).
    @Test func selfCorrectionCueDoesNotLaunderAGroundedOmissionOfAnUnrelatedSentence() {
        let raw = "Test the parser. Actually deploy the parser. Update docs."
        let out = "Deploy the parser."
        let v = EnhancementSanityCheck.detect(raw: raw, output: out)
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.sentenceDrop)) }
    }

    /// The legitimate counterpart of the case above: collapsing the
    /// correction ("Test the parser" → "Actually deploy the parser") while
    /// KEEPING the unrelated "Update docs." sentence must stay clean.
    @Test func selfCorrectionCollapseThatKeepsTheUnrelatedSentenceStaysClean() {
        let raw = "Test the parser. Actually deploy the parser. Update docs."
        let out = "Deploy the parser. Update docs."
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out).isClean)
    }

    // MARK: - Set semantics: repetition must not dilute a hallucination

    /// Regression: per-occurrence counting let a hallucination hide behind
    /// repeating grounded words (4/6 by occurrence, clean); unique-token
    /// counting scores this 2/4 — correctly suspect.
    @Test func repeatedGroundedWordsDoNotDiluteAHallucination() {
        let raw = "restart the daemon"
        let out = "Restart the daemon. Restart the daemon. Launch missiles."
        let v = EnhancementSanityCheck.detect(raw: raw, output: out)
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

    // MARK: - Tightened edit distance: short tokens get zero fuzzy tolerance

    /// Regression: with the old "<10 chars → 1 edit" rule, three unrelated
    /// short words each sat one edit from a raw word and the whole output
    /// scored 3/3 grounded. Short tokens (<5 chars) now get threshold 0 —
    /// substring/vocab/exact match only.
    @Test func shortTokenFuzzyMatchesDoNotGround() {
        let v = EnhancementSanityCheck.detect(raw: "can you fix the app", output: "Cat fox ape.")
        #expect(v.isSuspect)
        if case let .suspect(reasons) = v { #expect(reasons.contains(.lowGroundedFraction)) }
    }

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
}
