import XCTest
import SwiftUI
import AppKit
@testable import Sotto

final class SyntaxHighlighterTests: XCTestCase {

    // MARK: - isLikelyCode

    func test_isLikelyCode_falseForProse() {
        XCTAssertFalse(SyntaxHighlighter.isLikelyCode(
            "Hey, let me know if you can make the meeting tomorrow afternoon."
        ))
        XCTAssertFalse(SyntaxHighlighter.isLikelyCode(
            "The variable cost of living keeps rising, so we should return the favor."
        ))
    }

    func test_isLikelyCode_falseForTooShort() {
        XCTAssertFalse(SyntaxHighlighter.isLikelyCode("func x"))
        XCTAssertFalse(SyntaxHighlighter.isLikelyCode(""))
    }

    func test_isLikelyCode_trueForSwift() {
        XCTAssertTrue(SyntaxHighlighter.isLikelyCode(
            "func handleRetry(count: Int) {\n    return count + 1;\n}"
        ))
    }

    func test_isLikelyCode_trueForPython() {
        XCTAssertTrue(SyntaxHighlighter.isLikelyCode(
            "def handle_retry(count):\n    return count + 1"
        ))
    }

    func test_isLikelyCode_trueForShellish() {
        XCTAssertTrue(SyntaxHighlighter.isLikelyCode(
            "import os;\nconst x = os.environ();"
        ))
    }

    // MARK: - highlight

    func test_highlight_preservesPlainText() {
        let source = "func add(a: Int) {\n    return a + 1\n}"
        let attr = SyntaxHighlighter.highlight(source)
        XCTAssertEqual(String(attr.characters), source,
                       "highlight must never alter the underlying text")
    }

    func test_highlight_assignsMultipleColors() {
        // keyword (func/return) + function call (add) + number (1) → ≥3 hues
        // beyond a single flat color.
        let source = "func add() {\n    return doWork(1)\n}"
        // NSColor foreground attributes live in the AppKit scope; round-trip
        // through NSAttributedString to read them back the way SwiftUI renders.
        let ns = NSAttributedString(SyntaxHighlighter.highlight(source))
        var colors = Set<String>()
        ns.enumerateAttribute(.foregroundColor,
                              in: NSRange(location: 0, length: ns.length)) { value, _, _ in
            if let color = value as? NSColor { colors.insert(color.description) }
        }
        XCTAssertGreaterThanOrEqual(colors.count, 3,
            "a rich code snippet should tint keywords/calls/numbers distinctly; got \(colors.count)")
    }

    func test_highlight_emptyStringIsSafe() {
        let attr = SyntaxHighlighter.highlight("")
        XCTAssertEqual(String(attr.characters), "")
    }
}
