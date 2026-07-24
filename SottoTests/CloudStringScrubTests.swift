import XCTest

/// Locks the model + enhancement surfaces to on-device vocabulary. This fork is
/// on-device-only — cloud transcription, remote LLM providers, and API-key entry
/// were all removed in earlier work. This content-scan test guards against
/// residual (or regressed) user-facing cloud/API-key copy leaking back onto the
/// live Models settings tab and the enhancement surfaces it mounts.
///
/// It reads the live surface source files and asserts that no *double-quoted
/// string literal* (i.e. user-facing copy — not identifiers, not comments)
/// matches the cloud denylist. Pure comment lines are skipped so internal notes
/// like `// none requires an API key` and code identifiers like
/// `isAPIKeyValid` never trip the scan; the denylist requires a separator in
/// `api[ -]key`, so the bare identifier could not match even inside a literal.
final class CloudStringScrubTests: XCTestCase {

    /// Live model + enhancement surfaces, relative to the repo root. These are
    /// the screens reachable from the Models settings tab and the enhancement
    /// picker / prompt editor — the surfaces the negative intent anchor covers.
    private static let scopedSurfaces = [
        "Sotto/Views/Settings/Tabs/ModelsTab.swift",
        "Sotto/Views/Components/EnhancementSettingsPanel.swift",
        "Sotto/Services/AIEnhancement/AIEnhancementService.swift",
    ]

    /// Cloud / API-key vocabulary (and cloud-provider doc URLs) that must not
    /// appear in user-facing copy. `api[ -]key` mandates a separator so it
    /// matches the literal phrase "API key" but never the identifier
    /// `isAPIKeyValid`; `openai\.com` locks out cloud-era learn-more links such
    /// as the OpenAI cookbook URL the dead ModelSettingsView used to carry.
    private static let denylist = "(api[ -]key|cloud|openai\\.com|openai|anthropic|\\bgroq\\b|gemini)"

    private func repoRoot(from filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()   // SottoTests/
            .deletingLastPathComponent()   // repo root
    }

    /// Returns `"file:line  literal"` for every offending user-facing string
    /// literal across the scoped surfaces.
    private func offenders() -> [String] {
        let root = repoRoot()
        var hits: [String] = []

        for rel in Self.scopedSurfaces {
            let url = root.appendingPathComponent(rel)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                XCTFail("could not read scoped surface: \(rel)")
                continue
            }

            for (idx, rawLine) in text.components(separatedBy: .newlines).enumerated() {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                // Skip pure comment lines — internal notes are not user-facing.
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") {
                    continue
                }
                // Inspect only the contents of double-quoted string literals on
                // this line, so identifiers and code never trip the denylist.
                for literal in doubleQuotedLiterals(in: rawLine) {
                    if literal.range(
                        of: Self.denylist,
                        options: [.regularExpression, .caseInsensitive]
                    ) != nil {
                        hits.append("\(rel):\(idx + 1)  \"\(literal)\"")
                    }
                }
            }
        }
        return hits
    }

    private func doubleQuotedLiterals(in line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\"([^\"]*)\"") else { return [] }
        let ns = line as NSString
        return regex
            .matches(in: line, range: NSRange(location: 0, length: ns.length))
            .compactMap { m in
                guard m.numberOfRanges > 1 else { return nil }
                return ns.substring(with: m.range(at: 1))
            }
    }

    func test_modelAndEnhancementSurfaces_haveNoUserFacingCloudVocabulary() {
        let found = offenders()
        XCTAssertTrue(
            found.isEmpty,
            "User-facing cloud/API-key copy must not appear on the model/enhancement surfaces:\n"
                + found.joined(separator: "\n")
        )
    }
}
