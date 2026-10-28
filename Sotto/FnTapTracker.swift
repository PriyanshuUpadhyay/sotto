import Foundation

/// Tap-vs-chord decision for the Fn hotkey in Toggle mode: a tap (down→up with
/// no other key pressed during the hold) fires; Fn held as a modifier (Fn+F12)
/// suppresses. Pure state; HotkeyManager owns the NSEvent monitors that feed it.
struct FnTapTracker {
    private var isHeld = false
    private var chorded = false

    mutating func fnDown() {
        guard !isHeld else { return } // flags-changed blip mid-hold: keep chord state
        isHeld = true
        chorded = false
    }

    mutating func otherKeyDown() {
        if isHeld { chorded = true }
    }

    mutating func fnUp() -> Bool {
        defer { isHeld = false; chorded = false }
        return isHeld && !chorded
    }
}
