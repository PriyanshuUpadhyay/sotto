import Foundation

/// What macOS does on its own when the Fn (🌐) key is pressed — System
/// Settings › Keyboard › "Press 🌐 key to". With Fn as Sotto's hotkey, any
/// action other than "Do Nothing" also fires, and "Show Emoji & Symbols" opens
/// the picker, which takes focus and swallows Sotto's paste.
enum GlobeKeyAction: Equatable {
    case doNothing
    case changeInputSource
    case showEmojiAndSymbols
    case startDictation
    /// The key is missing or holds a value this build does not know.
    case unknown

    /// Maps the raw `AppleFnUsageType` value in `com.apple.HIToolbox`.
    init(rawValue: Any?) {
        switch (rawValue as? NSNumber)?.intValue {
        case 0: self = .doNothing
        case 1: self = .changeInputSource
        case 2: self = .showEmojiAndSymbols
        case 3: self = .startDictation
        default: self = .unknown
        }
    }

    /// Reads the current system setting. Sotto is not sandboxed, so it can
    /// read the global HIToolbox domain.
    static func current() -> GlobeKeyAction {
        GlobeKeyAction(rawValue: CFPreferencesCopyAppValue(
            "AppleFnUsageType" as CFString,
            "com.apple.HIToolbox" as CFString
        ))
    }

    /// The wording macOS uses in its Keyboard settings menu.
    var systemLabel: String? {
        switch self {
        case .doNothing: return "Do Nothing"
        case .changeInputSource: return "Change Input Source"
        case .showEmojiAndSymbols: return "Show Emoji & Symbols"
        case .startDictation: return "Start Dictation"
        case .unknown: return nil
        }
    }

    static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
}
