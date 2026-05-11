import Testing
import Foundation
@testable import VoiceInk

struct SeededAppPresetsTests {

    private func freshDefaults() -> UserDefaults {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func firstSeedAppendsThreePresetsAndSetsFlag() {
        let defaults = freshDefaults()
        var configs: [PowerModeConfig] = []

        let didSeed = SeededAppPresets.seedIfNeeded(into: &configs, userDefaults: defaults)

        #expect(didSeed == true)
        #expect(configs.count == 3)
        #expect(defaults.bool(forKey: "seededAppPresets_v1") == true)
    }

    @Test func secondSeedOnSameDefaultsIsNoOp() {
        let defaults = freshDefaults()
        var configs: [PowerModeConfig] = []

        SeededAppPresets.seedIfNeeded(into: &configs, userDefaults: defaults)
        let countAfterFirst = configs.count

        let didSeedAgain = SeededAppPresets.seedIfNeeded(into: &configs, userDefaults: defaults)

        #expect(didSeedAgain == false)
        #expect(configs.count == countAfterFirst)
    }

    @Test func slackPresetMatchesSpec() {
        let defaults = freshDefaults()
        var configs: [PowerModeConfig] = []
        SeededAppPresets.seedIfNeeded(into: &configs, userDefaults: defaults)

        let slack = configs.first { $0.name == "Slack" }
        #expect(slack != nil)
        let bundles = slack?.appConfigs?.map(\.bundleIdentifier) ?? []
        #expect(bundles.contains("com.tinyspeck.slackmacgap"))
        #expect(slack?.selectedPrompt == "Chat")
        #expect(slack?.useClipboardContext == true)
        #expect(slack?.useScreenCapture == false)
        #expect(slack?.autoSendKey == .commandEnter)
    }

    @Test func ghosttyPresetMatchesSpec() {
        let defaults = freshDefaults()
        var configs: [PowerModeConfig] = []
        SeededAppPresets.seedIfNeeded(into: &configs, userDefaults: defaults)

        let ghostty = configs.first { $0.name == "Ghostty" }
        #expect(ghostty != nil)
        let bundles = ghostty?.appConfigs?.map(\.bundleIdentifier) ?? []
        #expect(bundles == ["com.mitchellh.ghostty"])
        #expect(ghostty?.selectedPrompt == nil)
        #expect(ghostty?.useClipboardContext == true)
        #expect(ghostty?.useScreenCapture == false)
        #expect(ghostty?.autoSendKey == AutoSendKey.none)
    }

    @Test func claudeCodePresetMatchesSpec() {
        let defaults = freshDefaults()
        var configs: [PowerModeConfig] = []
        SeededAppPresets.seedIfNeeded(into: &configs, userDefaults: defaults)

        let claudeCode = configs.first { $0.name == "Claude Code" }
        #expect(claudeCode != nil)
        let bundles = Set(claudeCode?.appConfigs?.map(\.bundleIdentifier) ?? [])
        #expect(bundles.contains("com.mitchellh.ghostty"))
        #expect(bundles.contains("com.googlecode.iterm2"))
        #expect(bundles.contains("com.apple.Terminal"))
        #expect(claudeCode?.selectedPrompt == nil)
        #expect(claudeCode?.useClipboardContext == true)
        #expect(claudeCode?.useScreenCapture == false)
        #expect(claudeCode?.autoSendKey == AutoSendKey.none)
    }

    @Test func everyPresetUsesClipboardContext() {
        let defaults = freshDefaults()
        var configs: [PowerModeConfig] = []
        SeededAppPresets.seedIfNeeded(into: &configs, userDefaults: defaults)

        for config in configs {
            #expect(config.useClipboardContext == true)
            #expect(config.useScreenCapture == false)
        }
    }

    @Test func presetsAreEditableNotLocked() {
        let defaults = freshDefaults()
        var configs: [PowerModeConfig] = []
        SeededAppPresets.seedIfNeeded(into: &configs, userDefaults: defaults)

        configs[0].name = "Renamed"
        configs[0].useClipboardContext = false
        configs[0].autoSendKey = .enter

        #expect(configs[0].name == "Renamed")
        #expect(configs[0].useClipboardContext == false)
        #expect(configs[0].autoSendKey == .enter)
    }

    @Test func seedWhenFlagAlreadyTrueDoesNotAppend() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "seededAppPresets_v1")
        var configs: [PowerModeConfig] = []

        let didSeed = SeededAppPresets.seedIfNeeded(into: &configs, userDefaults: defaults)

        #expect(didSeed == false)
        #expect(configs.isEmpty)
    }
}
