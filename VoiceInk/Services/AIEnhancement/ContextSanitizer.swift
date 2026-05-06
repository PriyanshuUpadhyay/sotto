import Foundation

/// Phase A T5 — bounds context block size and strips secret-shaped lines.
/// Defense-in-depth: the user's primary protection is not pasting secrets
/// into a clipboard they then dictate alongside; this is a backstop.
///
/// Tail-prefer truncation: for paste-into targets, recent content is more
/// relevant than older. Truncation cuts at line boundaries to avoid invalid
/// UTF-8 and to keep the prepended "…[truncated]…" marker honest.
///
/// Idempotent: sanitize(sanitize(x, n), n) == sanitize(x, n).
enum ContextSanitizer {
    static func sanitize(_ raw: String, maxBytes: Int) -> String {
        let redacted = redactSecretLines(in: raw)
        return truncateToTail(redacted, maxBytes: maxBytes)
    }

    /// Word-boundary anchored to avoid `secretary`-class false positives;
    /// requires `:` or `=` separator + at least one non-space value char.
    private static let keyShapePattern = try! NSRegularExpression(
        pattern: #"\b(password|passwd|api[_-]?key|apikey|access[_-]?token|auth[_-]?token|secret[_-]?key|client[_-]?secret|private[_-]?key|aws[_-]?secret|github[_-]?token)\b\s*[:=]\s*\S"#,
        options: [.caseInsensitive]
    )

    private static let authHeaderPattern = try! NSRegularExpression(
        pattern: #"\b(authorization|x-api-key)\s*:\s*\S+"#,
        options: [.caseInsensitive]
    )

    /// Bearer plus base64url-friendly token (`/`, `+`, `=` padding allowed).
    private static let bearerPattern = try! NSRegularExpression(
        pattern: #"\bbearer\s+[A-Za-z0-9._/+\-=]+\b"#,
        options: [.caseInsensitive]
    )

    private static func redactSecretLines(in input: String) -> String {
        let lines = input.components(separatedBy: "\n")
        let kept = lines.filter { line in
            let range = NSRange(location: 0, length: (line as NSString).length)
            if keyShapePattern.firstMatch(in: line, range: range) != nil { return false }
            if authHeaderPattern.firstMatch(in: line, range: range) != nil { return false }
            if bearerPattern.firstMatch(in: line, range: range) != nil { return false }
            return true
        }
        return kept.joined(separator: "\n")
    }

    private static let truncationMarker = "…[truncated]…\n"

    private static func truncateToTail(_ input: String, maxBytes: Int) -> String {
        let utf8Bytes = Array(input.utf8)
        guard utf8Bytes.count > maxBytes else { return input }

        // Walk forward from the byte cut-point to the next \n so the surviving
        // tail starts at a line boundary (and we don't slice a UTF-8 codepoint).
        let cutFrom = utf8Bytes.count - maxBytes
        var snap = cutFrom
        while snap < utf8Bytes.count, utf8Bytes[snap] != UInt8(ascii: "\n") { snap += 1 }
        if snap < utf8Bytes.count { snap += 1 }  // skip the newline itself

        let tailBytes = Array(utf8Bytes[snap..<utf8Bytes.count])
        guard let tail = String(bytes: tailBytes, encoding: .utf8) else {
            // Defense: if for any reason the snap landed on an invalid boundary,
            // bail to the un-truncated input. Better correctness than a corrupt
            // string going into the prompt.
            return input
        }

        // Idempotency: if the tail already starts with the marker (because this
        // is a re-sanitize), don't double-prepend.
        if tail.hasPrefix(truncationMarker) {
            return tail
        }
        return truncationMarker + tail
    }
}
