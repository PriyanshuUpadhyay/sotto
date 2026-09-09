import Foundation


@MainActor
class WhisperPrompt: ObservableObject {
    @Published var transcriptionPrompt: String = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? ""
    
    private let customPromptsKey = "CustomLanguagePrompts"
    
    // Store user-customized prompts
    private var customPrompts: [String: String] = [:]
    
    private let languagePrompts: [String: String] = [
        "en": "Hello, how are you doing? Nice to meet you.",
        // Romanized Hindi so whisper keeps Latin script instead of Devanagari.
        "hinglish": "Namaste, aap kaise hain? Aapse milkar bahut accha laga.",
        "default": ""
    ]
    
    init() {
        loadCustomPrompts()
        updateTranscriptionPrompt()
        
        // Setup notification observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: .languageDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleLanguageChange() {
        updateTranscriptionPrompt()
    }
    
    private func loadCustomPrompts() {
        if let savedPrompts = UserDefaults.standard.dictionary(forKey: customPromptsKey) as? [String: String] {
            customPrompts = savedPrompts
        }
    }
    
    private func saveCustomPrompts() {
        UserDefaults.standard.set(customPrompts, forKey: customPromptsKey)
        UserDefaults.standard.synchronize() // Force immediate synchronization
    }
    
    func updateTranscriptionPrompt() {
        // Get the currently selected language from UserDefaults
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        
        // Get the prompt for the selected language (custom if available, otherwise default)
        let basePrompt = getLanguagePrompt(for: selectedLanguage)
        let prompt = basePrompt.isEmpty ? "" : basePrompt
        
        transcriptionPrompt = prompt
        UserDefaults.standard.set(prompt, forKey: "TranscriptionPrompt")
        UserDefaults.standard.synchronize() // Force immediate synchronization
        
        // Notify that the prompt has changed
        NotificationCenter.default.post(name: .promptDidChange, object: nil)
    }
    
    func getLanguagePrompt(for language: String) -> String {
        // First check if there's a custom prompt for this language
        if let customPrompt = customPrompts[language], !customPrompt.isEmpty {
            return customPrompt
        }
        
        // Otherwise return the default prompt, with safe fallback
        return languagePrompts[language] ?? languagePrompts["default"] ?? ""
    }
    
    func setCustomPrompt(_ prompt: String, for language: String) {
        customPrompts[language] = prompt
        saveCustomPrompts()
        updateTranscriptionPrompt()
        
        // Force update the UI
        objectWillChange.send()
    }
}
