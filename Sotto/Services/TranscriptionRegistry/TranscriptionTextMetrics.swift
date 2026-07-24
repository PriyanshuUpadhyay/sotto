import Foundation

enum TranscriptionTextMetrics {
    struct ErrorRates: Equatable {
        let wordErrorRate: Double
        let characterErrorRate: Double
    }

    static func errorRates(reference: String, hypothesis: String) -> ErrorRates {
        ErrorRates(
            wordErrorRate: wordErrorRate(reference: reference, hypothesis: hypothesis),
            characterErrorRate: characterErrorRate(reference: reference, hypothesis: hypothesis)
        )
    }

    static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let referenceWords = words(in: reference)
        let hypothesisWords = words(in: hypothesis)
        return normalizedDistance(reference: referenceWords, hypothesis: hypothesisWords)
    }

    static func characterErrorRate(reference: String, hypothesis: String) -> Double {
        let referenceCharacters = Array(reference)
        let hypothesisCharacters = Array(hypothesis)
        return normalizedDistance(reference: referenceCharacters, hypothesis: hypothesisCharacters)
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func normalizedDistance<T: Equatable>(reference: [T], hypothesis: [T]) -> Double {
        guard !reference.isEmpty else {
            return hypothesis.isEmpty ? 0 : 1
        }
        return Double(levenshteinDistance(reference, hypothesis)) / Double(reference.count)
    }

    private static func levenshteinDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + substitutionCost
                )
            }
            swap(&previous, &current)
        }

        return previous[b.count]
    }
}
