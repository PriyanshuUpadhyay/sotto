import AppKit

/// W12.E Scratchpad window. Activatable (unlike `MiniRecorderPanel`) so the
/// hosted `TextEditor` can become first responder, ⌘T/⌘W chord routing
/// works, and the dictation-into-place hook can read selectedRange. See plan
/// `docs/superpowers/plans/W12E-scratchpad.md` §Task 4.
final class ScratchpadWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
