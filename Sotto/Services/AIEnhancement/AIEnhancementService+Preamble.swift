import Foundation

extension AIEnhancementService {
    /// Belt-and-suspenders: strip the conversational preamble Apple's 3B
    /// foundation model sometimes emits despite explicit "no preamble"
    /// instructions. Examples: "Sure, here's a cleaned-up version:\n\n<content>"
    ///
    /// Narrowed to lines that open with a recognized meta-response phrase —
    /// stripping every line merely ending in ':' also deleted legitimate list
    /// lead-ins the prompt itself mandates ("We need three things:\n1. Auth…").
    ///
    /// `unconditionalPreambleHeads` are never a legitimate dictation lead-in
    /// (nobody dictates a list that starts "Sure," or "Of course,") — always
    /// stripped, list or no list. `listCapablePreambleHeads` ("here's"/"here
    /// is"/"here are") overlap the prompt's own list few-shot ("We need three
    /// things:\n1. Auth…" — "here's"/"here are" are common paraphrases of the
    /// same lead-in), so THOSE are only stripped when what follows is not a
    /// list. `nonisolated` — pure, no dependency on the class's @MainActor
    /// instance state, and used directly by tests (not just `performEnhance`).
    ///
    /// A speaker can open with the same words ("Okay, I need…", "Here is the
    /// problem…"), so a first line that starts with the transcript's own first
    /// words is content and stays.
    nonisolated static func stripPreamble(_ raw: String, transcript: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: "\n")
        guard let first = lines.first, lines.count >= 2 else { return trimmed }
        let firstLower = first.lowercased().trimmingCharacters(in: .whitespaces)

        let spokenOpener = leadingWords(transcript, count: 3)
        if !spokenOpener.isEmpty, leadingWords(first, count: spokenOpener.count) == spokenOpener {
            return trimmed
        }

        let isUnconditionalPreamble = unconditionalPreambleHeads.contains(where: { firstLower.hasPrefix($0) })
        let isListCapablePreamble = listCapablePreambleHeads.contains(where: { firstLower.hasPrefix($0) })
        guard isUnconditionalPreamble || isListCapablePreamble else { return trimmed }

        if isListCapablePreamble, !isUnconditionalPreamble,
           let nextNonEmpty = lines.dropFirst().first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           looksLikeListItem(nextNonEmpty) {
            return trimmed
        }

        let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? trimmed : rest
    }

    private nonisolated static let unconditionalPreambleHeads = [
        "sure,", "sure!", "sure.", "of course", "okay,", "got it", "no problem", "absolutely",
        "i've cleaned", "i have cleaned", "i'll clean", "below is", "the cleaned",
    ]
    private nonisolated static let listCapablePreambleHeads = ["here's", "here is", "here are"]

    /// The first `count` words, lowercased, with punctuation and apostrophe
    /// style ignored, so "okay i need" matches "Okay, I need".
    private nonisolated static func leadingWords(_ text: String, count: Int) -> [String] {
        let words = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
        return words.prefix(count).map(String.init)
    }

    /// A line that opens a list item: "- x", "* x", "• x", "1. x", "2) x".
    nonisolated static func looksLikeListItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return false }
        if "-*•".contains(first) { return t.dropFirst().first == " " }
        let digits = t.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return false }
        var rest = t.dropFirst(digits.count)
        guard let marker = rest.first, ".)".contains(marker) else { return false }
        rest = rest.dropFirst()
        return rest.first == " "
    }
}
