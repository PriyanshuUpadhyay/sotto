import XCTest
import SwiftData
@testable import Sotto

/// Guards the split of AIEnhancementService.swift into files under the
/// pre-commit token limit, with no behavior change.
@MainActor
final class AIEnhancementSplitTests: XCTestCase {

    // MARK: - Size limit

    /// `~/.local/bin/git-token-limit` refuses a staged file over 20,000 bytes.
    func testEveryAIEnhancementFileIsUnderTheByteLimit() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SottoTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sotto/Services/AIEnhancement")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .filter { $0.lastPathComponent.hasPrefix("AIEnhancementService") || $0.lastPathComponent == "EnhancementError.swift" }
        XCTAssertGreaterThanOrEqual(files.count, 2, "split set is too small: \(files.map(\.lastPathComponent))")
        for file in files {
            let size = try Data(contentsOf: file).count
            XCTAssertLessThanOrEqual(size, 20_000, "\(file.lastPathComponent) is \(size) bytes")
        }
    }

    // MARK: - EnhancementError / EnhancementGuardOutcome

    func testEnhancementErrorDescriptionsAreUnchanged() {
        XCTAssertEqual(EnhancementError.notConfigured.errorDescription,
                       "Enhancement is unavailable. Enable Apple Intelligence in System Settings.")
        XCTAssertEqual(EnhancementError.invalidResponse.errorDescription,
                       "Invalid response from the on-device model.")
        XCTAssertEqual(EnhancementError.enhancementFailed.errorDescription,
                       "AI enhancement failed to process the text.")
        XCTAssertEqual(EnhancementError.networkError.errorDescription,
                       "Network connection failed. Check your internet.")
        XCTAssertEqual(EnhancementError.serverError.errorDescription,
                       "The on-device model encountered an error. Please try again later.")
        XCTAssertEqual(EnhancementError.rateLimitExceeded.errorDescription,
                       "Rate limit exceeded. Please try again later.")
        XCTAssertEqual(EnhancementError.timeout.errorDescription,
                       "Enhancement request timed out. Check your connection or increase the timeout duration.")
        XCTAssertEqual(EnhancementError.safetyRefusal.errorDescription,
                       "Apple Foundation Models declined this transcript (safety filter).")
        XCTAssertEqual(EnhancementError.customError("boom").errorDescription, "boom")
    }

    func testGuardOutcomeCasesAndRawValuesAreUnchanged() {
        XCTAssertEqual(EnhancementGuardOutcome.allCases.map(\.rawValue),
                       ["notRun", "none", "retryRecovered", "deterministicFallback"])
    }

    // MARK: - withEnhancementDeadline

    /// Operation errors other than the deadline pass through untouched.
    func testDeadlinePropagatesOperationError() async {
        do {
            _ = try await withEnhancementDeadline(seconds: 5.0) { () -> String in
                throw EnhancementError.customError("inner")
            }
            XCTFail("expected the operation error")
        } catch let error as EnhancementError {
            guard case .customError(let message) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(message, "inner")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - stripPreamble / looksLikeListItem (cases the Swift Testing suite lacks)

    func testStripPreambleStripsEveryUnconditionalHead() {
        let heads = ["Sure, here you go", "Sure! Done", "Sure. Done", "Okay, cleaned", "Got it", "No problem",
                     "Absolutely", "I've cleaned this up", "I have cleaned this up", "I'll clean this up",
                     "Below is the text", "The cleaned transcript"]
        for head in heads {
            XCTAssertEqual(AIEnhancementService.stripPreamble("\(head)\nWorking late.", transcript: "working late"), "Working late.", head)
        }
    }

    func testStripPreambleKeepsTextWhenNothingFollowsThePreamble() {
        XCTAssertEqual(AIEnhancementService.stripPreamble("Sure,\n\n  ", transcript: ""), "Sure,")
    }

    func testStripPreambleTrimsWhitespace() {
        XCTAssertEqual(AIEnhancementService.stripPreamble("  \nHello there.\n ", transcript: "hello there"), "Hello there.")
    }

    func testStripPreambleStripsHereIsBeforeProseButKeepsItBeforeABullet() {
        XCTAssertEqual(AIEnhancementService.stripPreamble("Here is the text:\nWorking late.", transcript: "working late"), "Working late.")
        let list = "Here is the plan:\n- Auth\n- Logging"
        XCTAssertEqual(AIEnhancementService.stripPreamble(list, transcript: "auth logging"), list)
    }

    func testLooksLikeListItemEdgeCases() {
        XCTAssertTrue(AIEnhancementService.looksLikeListItem("  - indented"))
        XCTAssertTrue(AIEnhancementService.looksLikeListItem("12. Twelve"))
        XCTAssertFalse(AIEnhancementService.looksLikeListItem(""))
        XCTAssertFalse(AIEnhancementService.looksLikeListItem("-nospace"))
        XCTAssertFalse(AIEnhancementService.looksLikeListItem("•nospace"))
        XCTAssertFalse(AIEnhancementService.looksLikeListItem("1.nospace"))
        XCTAssertFalse(AIEnhancementService.looksLikeListItem("1 Auth"))
        XCTAssertFalse(AIEnhancementService.looksLikeListItem("1: Auth"))
    }

    // MARK: - getSystemInstructions(activeApp:customVocabulary:) exact text

    private func makeService() -> (AIEnhancementService, ModelContainer) {
        let schema = Schema([
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self,
            Snippet.self,
            ScratchpadDocument.self,
            ScratchpadVersion.self
        ])
        let container = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return (AIEnhancementService(modelContext: container.mainContext), container)
    }

    func testSystemInstructionsExactTextWithoutVocabulary() async {
        let (service, container) = makeService()
        let text = await service.getSystemInstructions(activeApp: nil, customVocabulary: "")
        XCTAssertEqual(text, String(format: AIPrompts.customPromptTemplate, AIPrompts.cleanupRules))
        _ = container
    }

    func testSystemInstructionsSpliceRegisterDirectiveForEmailApp() async {
        let (service, container) = makeService()
        let text = await service.getSystemInstructions(
            activeApp: (name: "Mail", bundleID: "com.apple.mail"), customVocabulary: "")
        XCTAssertEqual(text, String(format: AIPrompts.customPromptTemplate,
                                    AIPrompts.cleanupRules + AppCategory.email.registerDirective))
        _ = container
    }

    /// Vocabulary section sits after the template, separated by a blank line, and ends the string.
    func testSystemInstructionsAppendVocabularySectionLast() async {
        let (service, container) = makeService()
        let base = String(format: AIPrompts.customPromptTemplate, AIPrompts.cleanupRules)
        let text = await service.getSystemInstructions(activeApp: nil, customVocabulary: "Redis, Kubernetes")
        XCTAssertTrue(text.hasPrefix(base + "\n\nThe following are the user's vocabulary words, proper nouns, and technical terms."))
        XCTAssertTrue(text.hasSuffix("<CUSTOM_VOCABULARY>\nRedis, Kubernetes\n</CUSTOM_VOCABULARY>"))
        _ = container
    }
}
