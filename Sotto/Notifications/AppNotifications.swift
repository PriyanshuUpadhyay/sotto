import Foundation

extension Notification.Name {
    static let AppSettingsDidChange = Notification.Name("appSettingsDidChange")
    static let languageDidChange = Notification.Name("languageDidChange")
    static let promptDidChange = Notification.Name("promptDidChange")
    static let toggleMiniRecorder = Notification.Name("toggleMiniRecorder")
    static let dismissMiniRecorder = Notification.Name("dismissMiniRecorder")
    /// Posted by the Constellation failure HUD's RETRY chip. Consumed by
    /// `RecorderUIManager` to re-arm a fresh recording attempt after a
    /// surfaced failure — the same path a hotkey press would take.
    static let retryRecording = Notification.Name("retryRecording")
    static let didChangeModel = Notification.Name("didChangeModel")
    /// Posted by onboarding's model-tier step on finish. `userInfo["modelId"]`
    /// carries the selected tier's model name. Observed by
    /// `TranscriptionModelManager` to download that model (if not already usable)
    /// so first-run ends with a ready-to-use, auto-activated model.
    static let requestModelDownload = Notification.Name("requestModelDownload")
    static let aiProviderKeyChanged = Notification.Name("aiProviderKeyChanged")
    static let navigateToDestination = Notification.Name("navigateToDestination")
    static let selectSettingsTab = Notification.Name("selectSettingsTab")
    /// Posted by the Settings rail when a tab is chosen while a search query is
    /// active. `userInfo["tab"]` carries the target `SettingsTab`;
    /// `userInfo["label"]` carries the matching section's `searchLabel`. The
    /// destination tab scrolls that section to the top and briefly highlights it.
    static let selectSettingsSection = Notification.Name("selectSettingsSection")
    static let promptSelectionChanged = Notification.Name("promptSelectionChanged")
    static let transcriptionCreated = Notification.Name("transcriptionCreated")
    static let transcriptionCompleted = Notification.Name("transcriptionCompleted")
    static let transcriptionDeleted = Notification.Name("transcriptionDeleted")
    static let sessionMetricsDidChange = Notification.Name("sessionMetricsDidChange")
    static let enhancementToggleChanged = Notification.Name("enhancementToggleChanged")
    static let audioDeviceSwitchRequired = Notification.Name("audioDeviceSwitchRequired")

    /// Posted by `CursorPaster` after a successful paste keystroke. Carries the
    /// frontmost app name + a 1-line preview of the pasted text + a fresh
    /// timestamp via `userInfo[PasteEvent.userInfoKey]`. Consumed by
    /// `SottoEngine` to drive the Constellation `.done` state (P1.G).
    static let sottoDidPaste = Notification.Name("sottoDidPaste")

    /// Posted by the Command Palette when the user picks a transcript result.
    /// `userInfo["id"]` carries the `Transcription.id` (UUID). Consumed by
    /// `InlineHistoryView` to move its keyboard cursor (`focusedId`) onto that
    /// row and scroll it into view. Recent rows scroll immediately; rows below
    /// the loaded page set the cursor but won't auto-scroll until paged in (v1 gap).
    static let focusTranscription = Notification.Name("focusTranscription")
}
