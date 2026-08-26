import Foundation
import os

struct TranscriptionOutputFilter {
    private static let logger = Logger(subsystem: OSLogSubsystems.app, category: "TranscriptionOutputFilter")

    private static let hallucinationPatterns = [
        #"\[.*?\]"#,     // []
        #"\(.*?\)"#,     // ()
        #"\{.*?\}"#      // {}
    ]

    /// Strips the engine's hallucinations, drops the filler words, and tidies
    /// the whitespace. Pure, so every rule the transcript passes through is
    /// testable without `FillerWordManager` or its `UserDefaults` backing.
    static func cleaning(_ text: String, removeFillerWords: Bool, fillerWords: [String]) -> String {
        var result = removingTagBlocks(text)
        result = removingHallucinations(result)
        result = removingFillerWords(result, enabled: removeFillerWords, fillerWords: fillerWords)
        return tidyingWhitespace(result)
    }

    static func filter(_ text: String) -> String {
        let filteredText = cleaning(
            text,
            removeFillerWords: FillerWordManager.shared.isEnabled,
            fillerWords: FillerWordManager.shared.fillerWords
        )

        if filteredText != text {
            logger.notice("📝 Output filter result: \(filteredText, privacy: .public)")
        } else {
            logger.notice("📝 Output filter result (unchanged): \(filteredText, privacy: .public)")
        }

        return filteredText
    }

    /// Drops each listed filler word from `text` when removal is `enabled`.
    static func removingFillerWords(_ text: String, enabled: Bool, fillerWords: [String]) -> String {
        guard enabled else { return text }
        return fillerWords.reduce(text) { result, fillerWord in
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: fillerWord))\\b[,.]?"
            return replacingMatches(of: pattern, in: result, options: .caseInsensitive)
        }
    }

    /// Removes `<TAG>…</TAG>` blocks, which some engines emit around their own
    /// commentary rather than around dictated speech.
    private static func removingTagBlocks(_ text: String) -> String {
        replacingMatches(of: #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#, in: text)
    }

    private static func removingHallucinations(_ text: String) -> String {
        hallucinationPatterns.reduce(text) { result, pattern in
            replacingMatches(of: pattern, in: result)
        }
    }

    private static func tidyingWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Deletes every match of `pattern`. An unusable pattern is a defect in
    /// this file's literals, so the text passes through unchanged.
    private static func replacingMatches(
        of pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}
