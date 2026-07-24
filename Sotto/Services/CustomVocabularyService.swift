import Foundation
import SwiftUI
import SwiftData

class CustomVocabularyService {
    static let shared = CustomVocabularyService()

    private init() {}

    func getCustomVocabulary(from context: ModelContext) -> String {
        guard let customWords = getCustomVocabularyWords(from: context), !customWords.isEmpty else {
            return ""
        }

        let wordsText = customWords.joined(separator: ", ")
        return "Important Vocabulary: \(wordsText)"
    }

    private func getCustomVocabularyWords(from context: ModelContext) -> [String]? {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\VocabularyWord.word)])

        do {
            let items = try context.fetch(descriptor)
            let words = items.map { $0.word }
            return words.isEmpty ? nil : words
        } catch {
            return nil
        }
    }

    /// Seeds the custom vocabulary with recurring domain terms (the app name
    /// plus tooling/proper nouns the ASR reliably mishears), so they reach both
    /// the enhancement prompt and the phonetic corrector. Idempotent — each word
    /// is inserted only if a row with it doesn't already exist. Safe to call on
    /// every launch. Conservative on purpose: domain nouns only. A couple
    /// ("Opus", "Sonnet") are English-overloaded, but they're safe because
    /// correction requires the token to be OOV *and* pass the tight phonetic +
    /// Levenshtein gate — a correctly-spelled common word is never a candidate.
    func seedDefaultVocabularyIfNeeded(context: ModelContext) {
        let seedWords = [
            "Sotto", "Claude", "cmux", "Parakeet", "SwiftData",
            "Xcode", "Anthropic", "Opus", "Sonnet", "SQLite",
            "Gemini", "Atlas"
        ]
        for word in seedWords {
            let descriptor = FetchDescriptor<VocabularyWord>(
                predicate: #Predicate { $0.word == word }
            )
            let exists = (try? context.fetch(descriptor))?.isEmpty == false
            if !exists {
                context.insert(VocabularyWord(word: word))
            }
        }
        try? context.save()
    }
}
