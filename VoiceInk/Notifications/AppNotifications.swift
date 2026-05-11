import Foundation

extension Notification.Name {
    static let AppSettingsDidChange = Notification.Name("appSettingsDidChange")
    static let languageDidChange = Notification.Name("languageDidChange")
    static let promptDidChange = Notification.Name("promptDidChange")
    static let toggleMiniRecorder = Notification.Name("toggleMiniRecorder")
    static let dismissMiniRecorder = Notification.Name("dismissMiniRecorder")
    static let didChangeModel = Notification.Name("didChangeModel")
    static let aiProviderKeyChanged = Notification.Name("aiProviderKeyChanged")
    static let navigateToDestination = Notification.Name("navigateToDestination")
    static let promptSelectionChanged = Notification.Name("promptSelectionChanged")
    static let powerModeConfigurationApplied = Notification.Name("powerModeConfigurationApplied")
    static let transcriptionCreated = Notification.Name("transcriptionCreated")
    static let transcriptionCompleted = Notification.Name("transcriptionCompleted")
    static let transcriptionDeleted = Notification.Name("transcriptionDeleted")
    static let sessionMetricsDidChange = Notification.Name("sessionMetricsDidChange")
    static let enhancementToggleChanged = Notification.Name("enhancementToggleChanged")
    static let openFileForTranscription = Notification.Name("openFileForTranscription")
    static let audioDeviceSwitchRequired = Notification.Name("audioDeviceSwitchRequired")

    /// Posted by `CursorPaster` after a successful paste keystroke. Carries the
    /// frontmost app name + a 1-line preview of the pasted text + a fresh
    /// timestamp via `userInfo[PasteEvent.userInfoKey]`. Consumed by
    /// `VoiceInkEngine` to drive the Constellation `.done` state (P1.G).
    static let voiceInkDidPaste = Notification.Name("voiceInkDidPaste")
}
