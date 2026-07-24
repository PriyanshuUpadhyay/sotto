import AppKit

// MARK: - Active screen selection
//
// Floating UI (the recorder HUD, the review-before-paste editor, the post-paste
// review tray) must appear on the display the user is actually working on.
//
// They previously anchored to `NSScreen.main`. For Sotto — an accessory
// (`LSUIElement`) app that owns no key window — `NSScreen.main` resolves to the
// menu-bar / primary display, NOT the externally-focused one. So with an
// extended display the HUD and review panels stranded on the primary screen
// even while the user worked on (and pasted into) the external display: paste
// targets the keyboard-focused app via CGEvent, which is screen-agnostic, so it
// landed correctly while the UI did not follow.
//
// The mouse location is the reliable, always-available "active display" signal
// (what dictation apps like Handy use), so we pick the screen under the cursor,
// falling back to `NSScreen.main`.

/// Pure screen-selection logic, isolated from `NSScreen`/`NSEvent` so it is unit
/// testable.
enum ActiveScreenPicker {
    /// Index into `frames` of the screen the user is working on: the screen
    /// containing `mouse`, else `mainIndex` (what `NSScreen.main` yields), else 0.
    static func pick(mouse: CGPoint, frames: [CGRect], mainIndex: Int) -> Int {
        if let i = frames.firstIndex(where: { $0.contains(mouse) }) { return i }
        if frames.indices.contains(mainIndex) { return mainIndex }
        return 0
    }
}

extension NSScreen {
    /// The display the user is currently working on (the screen under the mouse),
    /// falling back to `main`. Use this instead of `NSScreen.main` for floating
    /// UI so it follows the user onto an extended display. See `ActiveScreenPicker`.
    static var active: NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let mainIndex = main.flatMap { screens.firstIndex(of: $0) } ?? 0
        let i = ActiveScreenPicker.pick(
            mouse: NSEvent.mouseLocation,
            frames: screens.map(\.frame),
            mainIndex: mainIndex
        )
        return screens[i]
    }
}
