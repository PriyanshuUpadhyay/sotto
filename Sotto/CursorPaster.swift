import Foundation
import AppKit
import Carbon
import ApplicationServices
import os

private let logger = Logger(subsystem: OSLogSubsystems.app, category: "CursorPaster")

/// Outcome of a `pasteAtCursor` call.
enum PasteOutcome {
    case pasted
    /// Cmd+V was posted but AX reported no focused element — on Electron apps
    /// (Slack, cmux) that report is routinely a false negative, so the paste
    /// probably landed.
    case pastedUnverified
    case clipboardOnly
}

class CursorPaster {

    /// `dictationGeneration` is X1/F6 acceptance-evidence plumbing: pass the
    /// active `AIEnhancementService.dictationGeneration` ONLY from the
    /// transcription pipeline's own paste call — every other caller ("Paste
    /// Last Transcription", the command palette) omits it, so their
    /// `PasteEvent`s carry no token and `handleDidPaste` ignores them for
    /// stop→paste telemetry purposes.
    @discardableResult
    static func pasteAtCursor(_ text: String, dictationGeneration: Int? = nil) -> PasteOutcome {
        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")

        // Remember the exact text we're about to paste so the post-paste ping's
        // Copy action reflects the LAST pasted text.
        lastPastedText = text

        // Capture the PRIOR clipboard UNCONDITIONALLY. The post-paste Review
        // Tray's Undo restores it regardless of the `restoreClipboardAfterPaste`
        // setting; that setting still gates only the AUTO-restore below. This
        // capture is additive — it must run before `setClipboard` overwrites it.
        // Privacy: SKIP items marked concealed/transient (password managers tag
        // copied secrets with `org.nspasteboard.ConcealedType`) so a secret is
        // never held in the process-lifetime static stash.
        let excludedTypes: Set<NSPasteboard.PasteboardType> = [
            NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
            NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        ]
        var savedContents: [(NSPasteboard.PasteboardType, Data)] = []
        let currentItems = pasteboard.pasteboardItems ?? []
        for item in currentItems {
            if item.types.contains(where: { excludedTypes.contains($0) }) { continue }
            for type in item.types {
                if let data = item.data(forType: type) {
                    savedContents.append((type, data))
                }
            }
        }

        // Capture the frontmost app NOW (before our 50ms delay below) so the
        // app reported in `PasteEvent` is the one that actually received the
        // paste — `NSWorkspace.frontmostApplication` after the keystroke fires
        // could already be a different app if the user app-switches in that
        // window. Bridges into `PasteEvent` for the Constellation done state.
        let targetApp = NSWorkspace.shared.frontmostApplication
        let pasteAppName = targetApp?.localizedName ?? "clipboard"
        let pastePreview = PasteEvent.preview(from: text)

        // AX focus check is ADVISORY ONLY — it never blocks the keystroke.
        // Electron apps (Slack, cmux) materialize their AX tree lazily, so the
        // systemwide query returns a confident "no element" while a compose box
        // IS focused; skipping Cmd+V on that answer silently dropped pastes
        // (KI-02). An unverified target only suppresses auto-send and keeps the
        // text recoverable (clipboard stays put + silent Scratchpad copy).
        let hasVerifiedTarget = focusedElementAcceptsText()

        // If the target is unverified, force non-transient and skip the timed
        // restore below so the text isn't restored away from under the user.
        ClipboardManager.setClipboard(text, transient: shouldRestoreClipboard && hasVerifiedTarget)

        if !hasVerifiedTarget {
            let targetBundleId = targetApp?.bundleIdentifier ?? "unknown"
            logger.notice("AX reports no focused element (app=\(targetBundleId, privacy: .public)) — pasting anyway. The text stays on the clipboard for recovery.")
        }

        // Stash the paste context so the post-paste ping's Undo can restore the
        // prior clipboard even after the ping panel takes key focus.
        lastPasteContext = PasteContext(
            priorClipboard: savedContents,
            targetApp: targetApp,
            appName: pasteAppName
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if UserDefaults.standard.bool(forKey: "useAppleScriptPaste") {
                pasteUsingAppleScript()
            } else {
                pasteFromClipboard()
            }

            // Plan §P1.G: emit a `PasteEvent` after the keystroke fires so
            // the Constellation orchestrator can derive `.done`. Posted on
            // the main queue (we're already on `.main`); `SottoEngine`
            // republishes via `lastPasteEvent`.
            let event = PasteEvent(
                appName: pasteAppName,
                preview: pastePreview,
                timestamp: Date(),
                dictationGeneration: dictationGeneration
            )
            NotificationCenter.default.post(
                name: .sottoDidPaste,
                object: nil,
                userInfo: [PasteEvent.userInfoKey: event]
            )

            // Commit haptic — co-located with the `.done`-deriving paste event so
            // sound (completion cue) + tactile confirmation land together. We are
            // already on `.main` (this is a `DispatchQueue.main.asyncAfter` body).
            MainActor.assumeIsolated {
                SottoFeedback.play(.commit)
            }
        }

        if shouldRestoreClipboard && hasVerifiedTarget {
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

        return hasVerifiedTarget ? .pasted : .pastedUnverified
    }

    /// ADVISORY verification that a focused element exists and accepts text.
    /// `false` no longer blocks the paste keystroke — it only downgrades the
    /// outcome to `.pastedUnverified` (auto-send suppressed, text kept
    /// recoverable). Electron apps (Slack, cmux) materialize their AX tree
    /// lazily, so this query routinely returns "no element" or errors while a
    /// compose box IS focused; the keystroke must fire regardless (Handy does
    /// zero detection and is reliable for exactly this reason).
    private static func focusedElementAcceptsText() -> Bool {
        guard AXIsProcessTrusted() else { return true }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard status == .success, let focusedRaw = focusedRef else {
            logger.notice("AX focus query found no element (status=\(status.rawValue, privacy: .public)) — target unverified")
            return false
        }
        let focused = focusedRaw as! AXUIElement

        var roleRef: CFTypeRef?
        let role: String?
        if AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef) == .success {
            role = roleRef as? String
        } else {
            // Role unreadable but an element IS focused → ambiguous → paste.
            role = nil
        }

        var settableRef: DarwinBoolean = false
        let isValueSettable = AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settableRef) == .success
            && settableRef.boolValue

        return acceptsTextForRole(role: role, hasFocusedElement: true, isValueSettable: isValueSettable)
    }

    /// Pure, testable classification behind `focusedElementAcceptsText`.
    /// Fail-open: returns false ONLY when nothing is focused. A focused element
    /// with a known-editable role OR a settable value accepts text; a focused
    /// element with an unknown/ambiguous/unreadable role also returns true so we
    /// paste anyway rather than false-negative on Electron compose boxes.
    static func acceptsTextForRole(role: String?, hasFocusedElement: Bool, isValueSettable: Bool) -> Bool {
        guard hasFocusedElement else { return false }

        let editableRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField",
            "AXWebArea",
            "AXContentEditable",
        ]
        if let role, editableRoles.contains(role) { return true }

        // Some apps (browsers, Electron) expose contenteditable via a settable
        // kAXValueAttribute.
        if isValueSettable { return true }

        // Focused element present but role unrecognized/unreadable → ambiguous →
        // fail open and paste.
        return true
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

        cmdDown?.flags = [.maskCommand, .maskNonCoalesced]
        vDown?.flags   = [.maskCommand, .maskNonCoalesced]
        vUp?.flags     = [.maskCommand, .maskNonCoalesced]
        cmdUp?.flags   = .maskNonCoalesced

        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        // Electron processes synthetic input asynchronously in the renderer; a
        // zero-spaced chord can batch cmdUp into the same input flush as vDown
        // and drop the paste (Slack). Hold Cmd ~100ms around the V click, as
        // Handy/enigo do. Auto-send fires at +0.5s, well after this release.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            cmdUp?.post(tap: .cghidEventTap)
            logger.notice("CGEvents posted for Cmd+V")
        }
    }

    // MARK: - Post-paste ping support

    /// Snapshot captured at paste time so the post-paste ping can act on the
    /// ORIGINAL target context AFTER it takes key focus from that app.
    struct PasteContext {
        /// Clipboard contents that existed BEFORE the paste overwrote them.
        let priorClipboard: [(NSPasteboard.PasteboardType, Data)]
        /// App that was frontmost (and received the paste) at paste time.
        let targetApp: NSRunningApplication?
        /// Display name of `targetApp` (matches `PasteEvent.appName`).
        let appName: String
    }

    /// Last paste's context. Read + written on the main thread (the paste path
    /// and the ping actions both run on `.main`).
    static var lastPasteContext: PasteContext?

    /// Exact text of the most recent paste — drives the ping's Copy action.
    static var lastPastedText: String?

    /// Undo action — restore the clipboard contents that preceded the paste.
    /// Does NOT remove the pasted text from the target app. No-op when nothing
    /// was stashed or the prior clipboard was empty.
    static func restorePriorClipboard() {
        guard let ctx = lastPasteContext, !ctx.priorClipboard.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for (type, data) in ctx.priorClipboard {
            pasteboard.setData(data, forType: type)
        }
    }

    /// Copy action — put `text` back on the clipboard non-transiently so it
    /// survives until the user pastes it.
    static func copyToClipboard(_ text: String) {
        _ = ClipboardManager.setClipboard(text, transient: false)
    }
}
