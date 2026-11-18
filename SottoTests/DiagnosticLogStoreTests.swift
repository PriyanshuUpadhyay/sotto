import XCTest
import OSLog
@testable import Sotto

final class DiagnosticLogStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticLogStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func test_trimmed_keepsSmallDataUnchanged() {
        let data = Data("a\nb\n".utf8)
        XCTAssertEqual(DiagnosticLogStore.trimmed(data, to: 100), data)
    }

    func test_trimmed_dropsOldestLinesAndStartsOnALineBoundary() {
        let lines = (0..<100).map { String(format: "line %03d\n", $0) }.joined()
        let data = Data(lines.utf8)   // 900 bytes
        let result = DiagnosticLogStore.trimmed(data, to: 500)

        XCTAssertLessThanOrEqual(result.count, 400)
        let text = String(decoding: result, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("line "), "must start at a whole line")
        XCTAssertTrue(text.hasSuffix("line 099\n"), "must keep the newest line")
    }

    func test_format_writesOneLineWithLevelAndCategory() {
        let line = DiagnosticLogStore.format(
            date: Date(timeIntervalSince1970: 0), level: .error, category: "CursorPaster", message: "hello"
        )
        XCTAssertTrue(line.hasSuffix(" error [CursorPaster] hello\n"))
        XCTAssertEqual(line.filter { $0 == "\n" }.count, 1)
    }

    func test_exportText_containsHeaderAndNewEntries() throws {
        let store = DiagnosticLogStore(fileURL: directory.appendingPathComponent("sotto.log"))
        store.start()
        _ = store.exportText()   // Waits for the launch marker, so the entry below is newer.

        let marker = "diagnostic-log-test-\(UUID().uuidString)"
        Logger(subsystem: OSLogSubsystems.app, category: "DiagnosticLogStoreTests")
            .notice("\(marker, privacy: .public)")

        let text = store.exportText()
        XCTAssertTrue(text.contains("accessibility trusted:"))
        XCTAssertTrue(text.contains("=== launch "))
        XCTAssertTrue(text.contains("[DiagnosticLogStoreTests] \(marker)"), "export must hold the new entry")
    }
}
