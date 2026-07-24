import Foundation

enum AppDefaults {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            // General
            "autoUpdateCheck": true,

            // Clipboard
            "restoreClipboardAfterPaste": true,
            "clipboardRestoreDelay": 2.0,
            "useAppleScriptPaste": false,

            // Audio & Media
            "isSystemMuteEnabled": true,
            "audioResumptionDelay": 0.0,
            "isPauseMediaEnabled": false,
            "isSoundFeedbackEnabled": true,

            // Recording & Transcription
            "IsTextFormattingEnabled": true,
            "IsVADEnabled": true,
            "RemoveFillerWords": true,
            "SelectedLanguage": "en",
            "AppendTrailingSpace": true,

            // Cleanup
            "IsTranscriptionCleanupEnabled": false,
            "TranscriptionRetentionMinutes": 1440,
            "IsAudioCleanupEnabled": false,
            "AudioRetentionPeriod": 7,

            // UI & Behavior
            "IsMenuBarOnly": false,

            // Enhancement
            "enhanceLevel": EnhanceLevel.default.rawValue,  // "light"
            "SkipShortEnhancement": true,
            "ShortEnhancementWordThreshold": 3,
            "EnhancementTimeoutSeconds": 15,
            "EnhancementRetryOnTimeout": true,
            "EnableEnhancementFailureNotification": true,
            "EnableContextSanitization": true,

            // Model
            "PrewarmModelOnWake": true,
            // W14.B — granular AFM-prewarm gate. PrewarmModelOnWake remains the
            // master switch; this lets users disable AFM warm specifically (for
            // empirical A/B of cold-vs-warm AFM ttft) without losing
            // transcription-model prewarm.
            "PrewarmAFMEnhancement": true,

        ])
    }
}
