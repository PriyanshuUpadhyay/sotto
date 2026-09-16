import XCTest
@testable import Sotto

final class GGUFProviderSmokeTests: XCTestCase {
    func testSmokeEnhancement() async throws {
        let modelURL = try XCTUnwrap(GGUFModelRegistry.fileURL(slug: "s1-mini"))
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: modelURL.path),
            "Skipping GGUF smoke test because s1-mini is not downloaded"
        )

        let provider = GGUFProvider(modelSlug: "s1-mini")
        let transcript =
            "so um i need to like send the the report by uh friday no wait make that thursday"
        let output = try await provider.enhance(
            systemPrompt: "",
            userPrompt: transcript,
            transcriptChars: transcript.count,
            callKind: .primary,
            generation: 0
        )

        XCTAssertFalse(output.isEmpty)
        XCTAssertTrue(output.contains("Thursday"), "Output was: \(output)")
        XCTAssertFalse(output.localizedCaseInsensitiveContains("<think>"))
    }
}

