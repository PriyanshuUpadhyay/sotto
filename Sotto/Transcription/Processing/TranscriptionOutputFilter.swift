import Foundation
import os

struct TranscriptionOutputFilter {
    private static let logger = Logger(subsystem: OSLogSubsystems.app, category: "TranscriptionOutputFilter")
    
    private static let hallucinationPatterns = [
        #"\[.*?\]"#,     // []
        #"\(.*?\)"#,     // ()
        #"\{.*?\}"#      // {}
    ]

    static func filter(_ text: String) -> String {
        var filteredText = text

        // Remove <TAG>...</TAG> blocks
        let tagBlockPattern = #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#
        if let regex = try? NSRegularExpression(pattern: tagBlockPattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        // Remove bracketed hallucinations
        for pattern in hallucinationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
            }
        }

        filteredText = removingFillerWords(
            filteredText,
            enabled: FillerWordManager.shared.isEnabled,
            fillerWords: FillerWordManager.shared.fillerWords
        )

        // Clean whitespace
        filteredText = filteredText.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Log results
        if filteredText != text {
            logger.notice("📝 Output filter result: \(filteredText, privacy: .public)")
        } else {
            logger.notice("📝 Output filter result (unchanged): \(filteredText, privacy: .public)")
        }

        return filteredText
    }

    /// Drops each listed filler word from `text` when removal is `enabled`.
    /// Pure, so the on/off and per-word list behavior is testable without
    /// touching `UserDefaults` or the `FillerWordManager` singleton.
    static func removingFillerWords(_ text: String, enabled: Bool, fillerWords: [String]) -> String {
        guard enabled else { return text }
        var result = text
        for fillerWord in fillerWords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: fillerWord))\\b[,.]?"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        return result
    }

} 
