import Foundation

enum SeededAppPresets {
    static let userDefaultsKey = "seededAppPresets_v1"

    @discardableResult
    static func seedIfNeeded(into configs: inout [PowerModeConfig], userDefaults: UserDefaults = .standard) -> Bool {
        if userDefaults.bool(forKey: userDefaultsKey) { return false }
        configs.append(contentsOf: presets())
        userDefaults.set(true, forKey: userDefaultsKey)
        return true
    }

    static func presets() -> [PowerModeConfig] {
        [slack(), ghostty(), claudeCode()]
    }

    private static func slack() -> PowerModeConfig {
        PowerModeConfig(
            name: "Slack",
            emoji: "💬",
            appConfigs: [AppConfig(bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack")],
            selectedPrompt: "Chat",
            useScreenCapture: false,
            useClipboardContext: true,
            autoSendKey: .commandEnter
        )
    }

    private static func ghostty() -> PowerModeConfig {
        PowerModeConfig(
            name: "Ghostty",
            emoji: "👻",
            appConfigs: [AppConfig(bundleIdentifier: "com.mitchellh.ghostty", appName: "Ghostty")],
            selectedPrompt: nil,
            useScreenCapture: false,
            useClipboardContext: true,
            autoSendKey: .none
        )
    }

    private static func claudeCode() -> PowerModeConfig {
        PowerModeConfig(
            name: "Claude Code",
            emoji: "🤖",
            appConfigs: [
                AppConfig(bundleIdentifier: "com.mitchellh.ghostty", appName: "Ghostty"),
                AppConfig(bundleIdentifier: "com.googlecode.iterm2", appName: "iTerm"),
                AppConfig(bundleIdentifier: "com.apple.Terminal", appName: "Terminal"),
            ],
            selectedPrompt: nil,
            useScreenCapture: false,
            useClipboardContext: true,
            autoSendKey: .none
        )
    }
}
