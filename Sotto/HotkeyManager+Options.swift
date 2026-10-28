import Foundation
import KeyboardShortcuts
import Carbon

extension HotkeyManager {
    enum HotkeyMode: String, CaseIterable {
        case toggle = "toggle"
        case pushToTalk = "pushToTalk"
        case hybrid = "hybrid"

        var displayName: String {
            switch self {
            case .toggle: return "Toggle"
            case .pushToTalk: return "Push to Talk"
            case .hybrid: return "Hybrid"
            }
        }
    }

    enum HotkeyOption: String, CaseIterable {
        case none = "none"
        case rightOption = "rightOption"
        case leftOption = "leftOption"
        case leftControl = "leftControl" 
        case rightControl = "rightControl"
        case fn = "fn"
        case rightCommand = "rightCommand"
        case rightShift = "rightShift"
        case custom = "custom"
        
        var displayName: String {
            switch self {
            case .none: return "None"
            case .rightOption: return "Right Option (⌥)"
            case .leftOption: return "Left Option (⌥)"
            case .leftControl: return "Left Control (⌃)"
            case .rightControl: return "Right Control (⌃)"
            case .fn: return "Fn"
            case .rightCommand: return "Right Command (⌘)"
            case .rightShift: return "Right Shift (⇧)"
            case .custom: return "Custom"
            }
        }
        
        var keyCode: CGKeyCode? {
            switch self {
            case .rightOption: return 0x3D
            case .leftOption: return 0x3A
            case .leftControl: return 0x3B
            case .rightControl: return 0x3E
            case .fn: return 0x3F
            case .rightCommand: return 0x36
            case .rightShift: return 0x3C
            case .custom, .none: return nil
            }
        }
        
        var isModifierKey: Bool {
            return self != .custom && self != .none
        }
    }

    /// The stored primary dictation hotkey, read without touching a live
    /// manager. `.rightCommand` is the shipped default, so this is what fires on
    /// a clean install.
    static var storedDictationHotkey: HotkeyOption {
        HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey1") ?? "") ?? .rightCommand
    }

    /// Unicode key-cap glyphs for a dictation hotkey option. Single-modifier
    /// options collapse to one cap (⌘/⌥/⌃/⇧/fn); `.custom` parses the recorded
    /// `KeyboardShortcuts.Shortcut`. Empty ⇒ nothing is bound, so a teaching
    /// surface must offer "set a shortcut" instead of a combo.
    static func dictationGlyphs(for option: HotkeyOption) -> [String] {
        switch option {
        case .none:
            return []
        case .custom:
            guard let s = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) else { return [] }
            var caps: [String] = []
            let m = s.modifiers
            if m.contains(.control) { caps.append("⌃") }
            if m.contains(.option)  { caps.append("⌥") }
            if m.contains(.shift)   { caps.append("⇧") }
            if m.contains(.command) { caps.append("⌘") }
            let modifierGlyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
            let keyPart = String(s.description.drop(while: { modifierGlyphs.contains($0) }))
            if !keyPart.isEmpty { caps.append(keyPart) }
            return caps
        case .rightOption, .leftOption:    return ["⌥"]
        case .leftControl, .rightControl:  return ["⌃"]
        case .fn:                          return ["fn"]
        case .rightCommand:                return ["⌘"]
        case .rightShift:                  return ["⇧"]
        }
    }
}
