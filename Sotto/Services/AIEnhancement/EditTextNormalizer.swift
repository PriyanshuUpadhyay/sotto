import Foundation
import CryptoKit

enum EditTextNormalizer {
    /// Collapse runs of whitespace to a single space and trim. Shared by the
    /// paste-time hash and the finalize-time diff baseline so autoformat /
    /// trailing-space / newline noise never registers as an edit.
    static func normalize(_ s: String) -> String {
        let collapsed = s.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }

    static func hash(_ s: String) -> String {
        let data = Data(normalize(s).utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
