import Foundation
import AppKit
import Carbon
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.VoiceInk", category: "CursorPaster")

class CursorPaster {

    static func pasteAtCursor(_ text: String) {
        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")

        var savedContents: [(NSPasteboard.PasteboardType, Data)] = []

        if shouldRestoreClipboard {
            let currentItems = pasteboard.pasteboardItems ?? []

            for item in currentItems {
                for type in item.types {
                    if let data = item.data(forType: type) {
                        savedContents.append((type, data))
                    }
                }
            }
        }

        // Detect whether anything is actually focused that can receive a paste.
        // If not, skip the Cmd+V (avoids system beep / "this content type is
        // not supported"-style errors from the frontmost app) and ensure the
        // text is on the clipboard non-transiently so the user can paste it
        // manually wherever they want.
        let hasPasteTarget = focusedElementAcceptsText()
        let mustForceClipboard = !hasPasteTarget

        // Set clipboard. If there's no paste target, force non-transient so
        // it doesn't get restored away from under the user.
        ClipboardManager.setClipboard(text, transient: shouldRestoreClipboard && !mustForceClipboard)

        if mustForceClipboard {
            logger.notice("No focused text field — text copied to clipboard, skipping paste keystroke")
            // W12.E paste-fallback: append the rescued text as a new
            // Scratchpad tab so the user can recover it via ⌥+S. Does NOT
            // open the Scratchpad window; the existing notification surfaces
            // the rescue. Migration policy #11 + plan §Task 8.
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: "Copied to clipboard (no text field focused)",
                    type: .info
                )
                if let container = ScratchpadModelContainerProvider.shared.modelContainer {
                    ScratchpadWindowController.shared.appendAsNewTab(
                        text: text, modelContainer: container
                    )
                }
            }
            return
        }

        // Capture the frontmost app NOW (before our 50ms delay below) so the
        // app reported in `PasteEvent` is the one that actually received the
        // paste — `NSWorkspace.frontmostApplication` after the keystroke fires
        // could already be a different app if the user app-switches in that
        // window. Bridges into `PasteEvent` for the Constellation done state.
        let pasteAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "clipboard"
        let pastePreview = PasteEvent.preview(from: text)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if UserDefaults.standard.bool(forKey: "useAppleScriptPaste") {
                pasteUsingAppleScript()
            } else {
                pasteFromClipboard()
            }

            // Plan §P1.G: emit a `PasteEvent` after the keystroke fires so
            // the Constellation orchestrator can derive `.done`. Posted on
            // the main queue (we're already on `.main`); `VoiceInkEngine`
            // republishes via `lastPasteEvent`.
            let event = PasteEvent(
                appName: pasteAppName,
                preview: pastePreview,
                timestamp: Date()
            )
            NotificationCenter.default.post(
                name: .voiceInkDidPaste,
                object: nil,
                userInfo: [PasteEvent.userInfoKey: event]
            )
        }

        if shouldRestoreClipboard {
            let restoreDelay = UserDefaults.standard.double(forKey: "clipboardRestoreDelay")
            let delay = max(restoreDelay, 0.25)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if !savedContents.isEmpty {
                    pasteboard.clearContents()
                    for (type, data) in savedContents {
                        pasteboard.setData(data, forType: type)
                    }
                }
            }
        }
    }

    /// Returns true if AX reports a focused element that can receive text input.
    /// Falls back to true (assume yes) if AX is denied or the query fails — the
    /// existing paste path still degrades gracefully via Cmd+V.
    private static func focusedElementAcceptsText() -> Bool {
        guard AXIsProcessTrusted() else { return true }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard status == .success, let focusedRaw = focusedRef else { return false }
        let focused = focusedRaw as! AXUIElement

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return false
        }

        let editableRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField",
            "AXWebArea",
            "AXContentEditable",
        ]
        if editableRoles.contains(role) { return true }

        // Some apps (browsers, Electron) expose contenteditable via subroles or
        // settable kAXValueAttribute. If kAXValueAttribute is settable, treat as
        // editable.
        var settableRef: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settableRef) == .success,
           settableRef.boolValue {
            return true
        }
        return false
    }

    // MARK: - AppleScript paste

    // "X – QWERTY ⌘" layouts remap to QWERTY when Command is held, so keystroke "v" resolves
    // the wrong key code. key code 9 (physical V) bypasses layout translation for those layouts.
    private static func makeScript(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }

    private static let pasteScriptKeystroke = makeScript("tell application \"System Events\" to keystroke \"v\" using command down")
    private static let pasteScriptKeyCode   = makeScript("tell application \"System Events\" to key code 9 using command down")

    private static var layoutSwitchesToQWERTYOnCommand: Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return false }
        return (Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String).hasSuffix("⌘")
    }

    private static func pasteUsingAppleScript() {
        let script = layoutSwitchesToQWERTYOnCommand ? pasteScriptKeyCode : pasteScriptKeystroke
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error = error {
            logger.error("AppleScript paste failed: \(error, privacy: .public)")
        }
    }

    // MARK: - CGEvent paste

    // Posts Cmd+V via CGEvent without modifying the active input source.
    private static func pasteFromClipboard() {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility not trusted — cannot paste")
            return
        }

        let source = CGEventSource(stateID: .privateState)

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp     = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        cmdDown?.flags = .maskCommand
        vDown?.flags   = .maskCommand
        vUp?.flags     = .maskCommand

        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)

        logger.notice("CGEvents posted for Cmd+V")
    }

    // MARK: - Auto Send Keys

    static func performAutoSend(_ key: AutoSendKey) {
        guard key.isEnabled else { return }
        guard AXIsProcessTrusted() else { return }

        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)

        switch key {
        case .none: return
        case .enter: break
        case .shiftEnter:
            enterDown?.flags = .maskShift
            enterUp?.flags   = .maskShift
        case .commandEnter:
            enterDown?.flags = .maskCommand
            enterUp?.flags   = .maskCommand
        }

        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
