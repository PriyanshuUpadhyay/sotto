import Foundation

/// The punctuation-mechanics bucket for the app the speaker is dictating into.
///
/// It selects sentence/end-punctuation conventions ONLY — never tone, wording,
/// or length. The cleanup rules own those, and `registerDirective` says so
/// explicitly; a directive that reached for style ("formal", "concise") would
/// contradict the rules' preserve-tone and no-paraphrase bounds.
///
/// Mapped deterministically in Swift from the frontmost app's bundle id — never
/// inferred by the model from context. This is the prompt-injection boundary:
/// every context section, `<ACTIVE_APP>` included, stays spelling-reference-only,
/// so only this Swift-computed value may reach the prompt as a directive.
enum AppCategory: String, Equatable {
    case email
    case workMessaging
    case personalMessaging
    case other

    /// Keys are lowercased; `from(bundleID:)` lowercases its input to match.
    private static let byBundleID: [String: AppCategory] = [
        "com.apple.mail": .email,
        "com.microsoft.outlook": .email,
        "com.readdle.smartemail-mac": .email,          // Spark
        "it.bloop.airmail2": .email,
        "org.mozilla.thunderbird": .email,
        "com.superhuman.electron": .email,

        "com.tinyspeck.slackmacgap": .workMessaging,
        "com.microsoft.teams": .workMessaging,
        "com.microsoft.teams2": .workMessaging,

        "com.apple.mobilesms": .personalMessaging,     // Messages
        "net.whatsapp.whatsapp": .personalMessaging,
        "ru.keepcoder.telegram": .personalMessaging,
        "org.telegram.desktop": .personalMessaging,
        "com.hnc.discord": .personalMessaging,
        "org.whispersystems.signal-desktop": .personalMessaging,
    ]

    static func from(bundleID: String?) -> AppCategory {
        guard let bundleID else { return .other }
        return byBundleID[bundleID.lowercased()] ?? .other
    }

    /// Sentence/punctuation mechanics only — never tone, wording, or length.
    /// A register that said "formal" or "concise" would contradict the cleanup
    /// rules' preserve-tone and no-paraphrase bounds, and invite the model to
    /// upgrade the style or drop content; the shared framing states the
    /// precedence so the two can never be read as peers.
    private var punctuationMechanic: String? {
        switch self {
        case .email:
            return "Email: keep complete sentences and standard end punctuation; add no greeting or sign-off."
        case .workMessaging:
            return "Work chat: keep complete sentences and standard end punctuation."
        case .personalMessaging, .other:
            // personalMessaging's one mechanic — dropping the trailing period on a
            // short single-sentence message — is applied deterministically in Swift
            // (`applyMechanics(to:)`), not left to the model. With no other mechanic
            // it carries no directive, mirroring `.other`.
            return nil
        }
    }

    /// Appended verbatim to the canonical cleanup rules. Empty for `.other` and
    /// `.personalMessaging`, which keep the neutral, register-free prompt.
    var registerDirective: String {
        guard let punctuationMechanic else { return "" }
        return """


        REGISTER — punctuation mechanics only. The cleanup rules above always take precedence: never change the speaker’s tone, wording, or length to suit it.
        \(punctuationMechanic)
        """
    }

    /// Deterministic post-pass over the enhanced output — the punctuation
    /// mechanics that can be applied in Swift instead of trusting the model.
    ///
    /// Only `.personalMessaging` acts: it strips the trailing period from a short
    /// single-sentence message (chat register). Multi-sentence output, other
    /// terminal marks (`?`/`!`/`…`), abbreviations/decimals (an interior `.`), and
    /// multi-line output are all left untouched. Every other category — and any
    /// output that fails those guards — is returned verbatim.
    ///
    /// Pure and idempotent. The em-dash (`--` → `—`) and straight→curly-quote
    /// mechanics are deliberately NOT applied here: both are unsafe on the
    /// technical dictation this app targets (`--verbose` is a CLI flag, not a
    /// dash; an apostrophe inside a code identifier must stay straight), and
    /// nothing in the output distinguishes prose from a code snippet.
    func applyMechanics(to text: String) -> String {
        guard self == .personalMessaging else { return text }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.last == ".", !trimmed.contains("\n") else { return text }

        let body = trimmed.dropLast()
        // An interior sentence terminator (incl. an ellipsis or an abbreviation/
        // decimal's dot) means this is not a single plain sentence — leave it.
        guard !body.contains(where: { ".!?…".contains($0) }) else { return text }

        let words = body.split(separator: " ")
        guard words.count <= Self.personalChatMaxWords else { return text }
        // A final-word abbreviation ("Main St.", "snacks etc.") owns its dot —
        // the interior-dot guard can't see it, so check the last word explicitly.
        if let last = words.last, Self.trailingAbbreviations.contains(last.lowercased()) {
            return text
        }

        return String(body)
    }

    private static let personalChatMaxWords = 8
    private static let trailingAbbreviations: Set<String> =
        ["etc", "vs", "dr", "mr", "mrs", "ms", "prof", "st", "ave", "approx"]
}
