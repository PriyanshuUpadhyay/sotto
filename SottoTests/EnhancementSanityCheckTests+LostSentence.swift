import Testing
import Foundation
@testable import Sotto

extension EnhancementSanityCheckTests {

    // MARK: - lostSentence: one real sentence gone from a long output

    /// A real dictation (judged as dropping a point): the model kept 3 of 4
    /// sentences, so the count ratio (0.75) passes `sentenceDrop`, but the
    /// whole "separate tables per service" sentence is gone.
    @Test func flagsOneDroppedSentenceTheCountRatioMisses() {
        let raw = "We should keep separate tables for every service in the database. The writer step takes most of the time. We can split the calls into multiple writers. Then we measure the latency again."
        let out = "The writer step takes most of the time. We can split the calls into multiple writers. Then we measure the latency again."
        #expect(!EnhancementSanityCheck.hasSentenceDrop(raw, out))
        #expect(EnhancementSanityCheck.hasLostSentence(raw, out))
        #expect(EnhancementSanityCheck.detect(raw: raw, output: out) == .suspect([.lostSentence]))
    }

    @Test func cleanRewriteThatKeepsEverySentenceIsNotLost() {
        let raw = "Um so the writer step is like taking loads of time. We can maybe split the calls into multiple writers."
        let out = "The writer step is taking a lot of time. We can maybe split the calls into multiple writers."
        #expect(!EnhancementSanityCheck.hasLostSentence(raw, out))
    }

    /// The prompt asks the model to drop the corrected version, so a
    /// sentence that the next one corrects must not count as lost.
    @Test func correctedSentenceMayGo() {
        let raw = "Deploy the parser service to staging tomorrow. Actually wait no, deploy the parser service to production tonight."
        let out = "Deploy the parser service to production tonight."
        #expect(!EnhancementSanityCheck.hasLostSentence(raw, out))
    }

    /// Fewer than 3 content words is too short to judge: "Okay, sounds
    /// good." reads the same as filler the prompt removes.
    @Test func shortSentenceIsNotJudged() {
        let raw = "Okay, sounds good. Let's move the encoder migration to the next sprint."
        let out = "Let's move the encoder migration to the next sprint."
        #expect(!EnhancementSanityCheck.hasLostSentence(raw, out))
    }

    @Test func vocabularyFixCoversTheMisheardWords() {
        let raw = "deploy cooper netties"
        let out = "Deploy Kubernetes."
        #expect(EnhancementSanityCheck.hasLostSentence(raw, out))
        #expect(!EnhancementSanityCheck.hasLostSentence(raw, out, ["kubernetes"]))
    }

    @Test func spokenNumbersRewrittenAsDigitsAreNotLost() {
        #expect(!EnhancementSanityCheck.hasLostSentence("pay one hundred and five dollars", "Pay 105 dollars."))
    }

    /// A dot inside a token is not a sentence end, so a file name does not
    /// split its sentence into fragments that each look lost.
    @Test func dotInsideATokenIsNotASentenceEnd() {
        let raw = "Update the retry helper in NetworkClient.swift to use exponential backoff."
        let out = "Update the retry helper in NetworkClient.swift to use exponential backoff."
        #expect(!EnhancementSanityCheck.hasLostSentence(raw, out))
    }
}
