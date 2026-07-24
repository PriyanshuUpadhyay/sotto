import Testing
import Foundation
import SwiftData
@testable import Sotto

@Suite struct CustomVocabularySeedTests {
    private func ctx() -> ModelContext {
        let schema = Schema([VocabularyWord.self])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try! ModelContainer(for: schema, configurations: [cfg]))
    }
    private func words(_ c: ModelContext) -> [String] {
        ((try? c.fetch(FetchDescriptor<VocabularyWord>())) ?? []).map { $0.word }
    }

    @Test("seeds the domain glossary terms on first launch")
    func seedsTerms() {
        let c = ctx()
        CustomVocabularyService.shared.seedDefaultVocabularyIfNeeded(context: c)
        let seeded = words(c)
        for term in ["Sotto", "Claude", "cmux", "Parakeet", "SwiftData",
                     "Xcode", "Anthropic", "Opus", "Sonnet", "SQLite",
                     "Gemini", "Atlas"] {
            #expect(seeded.contains(term))
        }
    }

    @Test("seeding is idempotent — no duplicates on repeated calls")
    func idempotent() {
        let c = ctx()
        CustomVocabularyService.shared.seedDefaultVocabularyIfNeeded(context: c)
        CustomVocabularyService.shared.seedDefaultVocabularyIfNeeded(context: c)
        let seeded = words(c)
        #expect(seeded.count == Set(seeded).count)
        #expect(seeded.filter { $0 == "Sotto" }.count == 1)
    }

    @Test("does not clobber pre-existing user terms")
    func preservesUserTerms() {
        let c = ctx()
        c.insert(VocabularyWord(word: "Foyer"))
        try? c.save()
        CustomVocabularyService.shared.seedDefaultVocabularyIfNeeded(context: c)
        #expect(words(c).contains("Foyer"))
    }
}
