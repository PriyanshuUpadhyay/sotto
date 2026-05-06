import Foundation

enum AppDefaults {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            // General
            "enableAnnouncements": true,
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
            "RecorderType": "mini",

            // Cleanup
            "IsTranscriptionCleanupEnabled": false,
            "TranscriptionRetentionMinutes": 1440,
            "IsAudioCleanupEnabled": false,
            "AudioRetentionPeriod": 7,

            // UI & Behavior
            "IsMenuBarOnly": false,
            "powerModeAutoRestoreEnabled": false,
            // Hotkey
            "isMiddleClickToggleEnabled": false,
            "middleClickActivationDelay": 200,

            // Enhancement
            "enhanceLevel": EnhanceLevel.default.rawValue,  // W12.A — "medium"
            "SkipShortEnhancement": true,
            "ShortEnhancementWordThreshold": 3,
            "EnhancementTimeoutSeconds": 15,
            "EnhancementRetryOnTimeout": true,
            "EnableEnhancementFailureNotification": true,
            "EnableMLXFallback": true,
            "EnableContextSanitization": true,
            "MLXIdleEvictSeconds": 1800,

            // Model
            "PrewarmModelOnWake": true,
            // W14.B — granular AFM-prewarm gate. PrewarmModelOnWake remains the
            // master switch; this lets users disable AFM warm specifically (for
            // empirical A/B of cold-vs-warm AFM ttft) without losing
            // transcription-model prewarm.
            "PrewarmAFMEnhancement": true,
            // W14.A — force `.mlx` selection to use real MLX inference instead
            // of W11.B's AFM-first routing. Default off (AFM-first stays).
            "ForceMLXOverAFM": false,

            // W12.C — Snippets
            "DebugLogSnippetExpansion": false,

            // Hands-free (W12.D)
            "HandsFreeVADThresholdDb": Double(-40.0),
            "HandsFreeSilenceDurationMs": 1500,
            "HandsFreeTriggerPhrasesJSON": #"["press enter","submit","send it","send message"]"#,

        ])
    }
}
