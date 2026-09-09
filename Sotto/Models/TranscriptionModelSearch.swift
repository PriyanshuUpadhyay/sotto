import Foundation

enum TranscriptionModelSearch {
    static func results(
        in models: [any TranscriptionModel],
        query: String
    ) -> [any TranscriptionModel] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return models.filter { model in
            let fields = [model.name, model.displayName, model.description, model.provider.rawValue, model.language]
                + Array(model.supportedLanguages.values)
            return terms.allSatisfy { term in
                fields.contains { $0.localizedStandardContains(term) }
                    || model.supportedLanguages[term.lowercased()] != nil
            }
        }
    }
}
