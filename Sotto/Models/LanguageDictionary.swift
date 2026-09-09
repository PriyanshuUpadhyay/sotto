import Foundation

enum LanguageDictionary {
    static let english = ["en": "English"]

    static func forProvider(isMultilingual: Bool, provider: ModelProvider = .whisper) -> [String: String] {
        guard isMultilingual else { return english }
        switch provider {
        case .whisper:
            return ["en": "English", "hinglish": "Hinglish", "auto": "Multilingual"]
        case .fluidAudio:
            // Parakeet detects the language itself; the picker is disabled for it.
            return ["en": "English", "auto": "Multilingual"]
        case .nativeApple:
            // SpeechAnalyzer needs an explicit locale and has no Hindi, so it stays English.
            return english
        }
    }
}

