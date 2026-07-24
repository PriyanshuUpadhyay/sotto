import XCTest

/// Guards the deletion of the orphaned Bay recorder subsystem
/// (Sotto/Views/Recorder/Bay/). After f01 rewired the recorder onto the
/// Constellation surface, the Bay tree had zero production references. These
/// tests assert the directory and its Bay production .swift files are gone; the
/// fact that the full app target still compiles proves nothing dangled.
final class BayRemovalTests: XCTestCase {

    private func recorderDir(from filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()   // SottoTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sotto/Views/Recorder", isDirectory: true)
    }

    func test_bayRecorderSubsystem_directoryRemoved() {
        let bayDir = recorderDir().appendingPathComponent("Bay", isDirectory: true)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: bayDir.path, isDirectory: &isDir)
        XCTAssertFalse(exists, "Orphaned Bay/ recorder subsystem must be deleted: \(bayDir.path)")
    }

    func test_noBayProductionSwiftFilesRemain() {
        let recorder = recorderDir()
        guard let walker = FileManager.default.enumerator(
            at: recorder, includingPropertiesForKeys: nil
        ) else { return }

        var offenders: [String] = []
        for case let url as URL in walker
        where url.pathExtension == "swift" && url.pathComponents.contains("Bay") {
            offenders.append(url.lastPathComponent)
        }
        XCTAssertTrue(offenders.isEmpty, "No Bay/ production .swift files may remain: \(offenders)")
    }

    func test_noBayOrStalactiteTokensInProduction() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SottoTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sotto", isDirectory: true)
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ) else { return XCTFail("could not enumerate Sotto/") }

        var offenders: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if text.range(of: #"\b(bay|stalactite)\b"#,
                          options: [.regularExpression, .caseInsensitive]) != nil {
                offenders.append(url.lastPathComponent)
            }
        }
        XCTAssertTrue(offenders.isEmpty,
            "No production .swift under Sotto/ may carry Bay/stalactite naming: \(offenders)")
    }
}
