import Foundation

class FillerWordManager: ObservableObject {
    static let shared = FillerWordManager()

    static let defaultFillerWords = [
        "uh", "um", "uhm", "umm", "uhh", "uhhh",
        "hmm", "hm", "mmm", "mm", "mh", "ehh"
    ]

    private static let fillerWordsKey = "FillerWords"
    private static let removeFillerWordsKey = "RemoveFillerWords"

    private let defaults: UserDefaults

    @Published var fillerWords: [String] {
        didSet {
            defaults.set(fillerWords, forKey: Self.fillerWordsKey)
        }
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.removeFillerWordsKey)
    }

    /// `fillerWords` overrides the persisted list; tests pass an isolated
    /// `defaults` domain so editing the list never touches the real one.
    init(defaults: UserDefaults = .standard, fillerWords: [String]? = nil) {
        self.defaults = defaults
        self.fillerWords = fillerWords
            ?? defaults.stringArray(forKey: Self.fillerWordsKey)
            ?? Self.defaultFillerWords
    }

    func addWord(_ word: String) -> Bool {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        guard !fillerWords.contains(where: { $0.lowercased() == normalized }) else { return false }
        fillerWords.append(normalized)
        return true
    }

    func removeWord(_ word: String) {
        fillerWords.removeAll { $0.lowercased() == word.lowercased() }
    }
}
