import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import Sotto

@MainActor
final class MenuBarContentTests: XCTestCase {

    private func makeTranscriptions() -> [Transcription] {
        (0..<5).map { i -> Transcription in
            let t = Transcription(text: "t\(i)", duration: 1)
            t.timestamp = Date(timeIntervalSinceReferenceDate: Double(i))
            return t
        }
    }

    func test_recentItems_capsAtThree_newestFirst() {
        let items = SottoMenuBarContent.recentItems(from: makeTranscriptions())
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.text), ["t4", "t3", "t2"])
    }

    func test_recentItems_respectsExplicitLimit() {
        XCTAssertEqual(SottoMenuBarContent.recentItems(from: makeTranscriptions(), limit: 2).count, 2)
    }

    func test_recentItems_prefersEnhancedTextForCopyPayload() {
        let t = Transcription(text: "raw", duration: 1, enhancedText: "enhanced")
        let items = SottoMenuBarContent.recentItems(from: [t])
        XCTAssertEqual(items.first?.text, "enhanced")
    }

    func test_recentItems_fallsBackToRawTextWhenNoEnhancement() {
        let t = Transcription(text: "raw", duration: 1)
        let items = SottoMenuBarContent.recentItems(from: [t])
        XCTAssertEqual(items.first?.text, "raw")
    }

    func test_statusText_reflectsEngineStateAndModel() {
        XCTAssertEqual(
            SottoMenuBarContent.statusText(state: .idle, modelDisplayName: "Parakeet V3"),
            "Ready · Parakeet V3"
        )
        XCTAssertEqual(
            SottoMenuBarContent.statusText(state: .recording, modelDisplayName: "Parakeet V3"),
            "Recording · Parakeet V3"
        )
    }

    func test_statusText_fallsBackToNoneWhenModelMissing() {
        XCTAssertEqual(
            SottoMenuBarContent.statusText(state: .idle, modelDisplayName: nil),
            "Ready · None"
        )
    }

    func test_statusLabel_distinguishesTranscribeAndEnhanceTail() {
        XCTAssertEqual(SottoMenuBarContent.statusLabel(for: .starting), "Starting…")
        XCTAssertEqual(SottoMenuBarContent.statusLabel(for: .transcribing), "Transcribing…")
        XCTAssertEqual(SottoMenuBarContent.statusLabel(for: .enhancing), "Enhancing…")
        XCTAssertEqual(SottoMenuBarContent.statusLabel(for: .busy), "Working…")
    }

    func test_sottoMenuBarContent_isConstructible() {
        _ = SottoMenuBarContent()
    }
}
