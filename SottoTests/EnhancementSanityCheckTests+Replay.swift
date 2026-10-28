import Testing
import Foundation
@testable import Sotto

extension EnhancementSanityCheckTests {

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
            name: "cuelessPartialRestatement",
            raw: "we wont be I'll be reviewing the plan and then we start",
            good: "I'll be reviewing the plan, and then we start.",
            bad: "You'll be reviewing the plan, and then you start."
        ),
        FewShot(
            name: "duplicatedPhraseComposio",
            raw: "we would want to move from move trivial tasks from Composio",
            good: "We would want to move trivial tasks from Composio.",
            bad: "Yes, we should move trivial tasks from Composio."
        ),
        FewShot(
            name: "midSentenceFalseStart",
            raw: "can you check the the upload transf transport later",
            good: "Can you check the upload transport later?",
            bad: "The transcript asks whether the upload transport was checked."
        ),
        FewShot(
            name: "cuelessSentenceRestart",
            raw: "we need to deploy the we need to test the migration before we deploy it",
            good: "We need to test the migration before we deploy it.",
            bad: "Yes, we should test the migration before we deploy it."
        ),
        FewShot(
            name: "ordinalList",
            raw: "we need three things first auth second logging third the retry policy",
            good: "We need three things:\n1. Auth\n2. Logging\n3. The retry policy",
            bad: "Based on the transcript, three things are needed: auth, logging, and the retry policy."
        ),
        FewShot(
            name: "spokenNumberList",
            raw: "my tasks are one update the brief two send it to Mina",
            good: "My tasks are:\n1. Update the brief\n2. Send it to Mina",
            bad: "Here are your tasks: update the brief and send it to Mina."
        ),
        FewShot(
            name: "numeralList",
            raw: "the steps are 1 install dependencies 2 run the tests 3 deploy the app",
            good: "The steps are:\n1. Install dependencies\n2. Run the tests\n3. Deploy the app",
            bad: "Here's how to install dependencies, run tests, and deploy the app."
        ),
        FewShot(
            name: "explicitCountList",
            raw: "i need four things milk eggs bread and butter",
            good: "I need four things:\n1. Milk\n2. Eggs\n3. Bread\n4. Butter",
            bad: "Here are four things you need: milk, eggs, bread, and butter."
        ),
        FewShot(
            name: "spokenQuantitySentence",
            raw: "i bought one apple and two bananas",
            good: "I bought 1 apple and 2 bananas.",
            bad: "You should buy 1 apple and 2 bananas."
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
}
