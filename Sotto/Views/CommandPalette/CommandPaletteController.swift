import SwiftUI
import AppKit

/// Owns the command-palette panel: a screen-covering transparent borderless
/// key window holding a dim scrim + centered onyx card. Captures the frontmost
/// app on open so paste/retry land in the real app, not this panel. Both the
/// app-focused ⌘K and the user-bindable global hotkey call `toggle(engine:)`.
@MainActor
final class CommandPaletteController: NSObject {
    static let shared = CommandPaletteController()

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private let model = CommandPaletteModel()
    private var capturedApp: NSRunningApplication?

    private override init() { super.init() }

    func toggle(engine: SottoEngine) {
        if panel != nil { close(); return }
        show(engine: engine)
    }

    private func show(engine: SottoEngine) {
        // Capture BEFORE we steal focus.
        capturedApp = NSWorkspace.shared.frontmostApplication

        model.setSource(CommandRegistry.all(engine: engine, query: ""))
        model.applyQuery("")

        let root = ZStack {
            Color.black.opacity(0.001)            // catches scrim taps
                .contentShape(Rectangle())
                .onTapGesture { [weak self] in self?.close() }
            CommandPalette(
                model: model,
                onRun: { [weak self] cmd, commandHeld in self?.run(cmd, commandHeld: commandHeld) },
                onClose: { [weak self] in self?.close() },
                onQueryChanged: { [weak self] query in
                    // Transcript rows come from a SwiftData predicate, so the
                    // source must be rebuilt for each query — otherwise the
                    // palette only ever searches the 6 rows fetched at open.
                    self?.model.setSource(CommandRegistry.all(engine: engine, query: query))
                }
            )
        }
        .background(Color.black.opacity(0.32).ignoresSafeArea())   // dim backdrop

        // AccentObserving: independent NSHostingController root — see MiniWindowManager.
        let host = NSHostingController(rootView: AccentObserving { root })

        let screen = (capturedApp.flatMap { _ in NSScreen.main }) ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let win = CommandPalettePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.contentViewController = host
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .modalPanel
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.setFrame(frame, display: true)
        panel = win

        // Become key (not just front) to receive typed text in the search field,
        // WITHOUT activating Sotto — `CommandPalettePanel` overrides `canBecomeKey`
        // so the borderless `.nonactivatingPanel` keys while the user's target app
        // (`capturedApp`) stays frontmost for paste-back.
        win.makeKeyAndOrderFront(nil)

        installKeyMonitor()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 125: self.model.moveSelection(by: 1);  return nil   // ↓
            case 126: self.model.moveSelection(by: -1); return nil   // ↑
            case 53:  self.close();                     return nil   // ⎋
            case 36, 76:                                              // ⏎ / numpad-⏎
                if let cmd = self.model.selectedCommand {
                    self.run(cmd, commandHeld: event.modifierFlags.contains(.command))
                }
                return nil
            default:
                return event
            }
        }
    }

    /// Runs a command. For transcript rows the action is paste-into-target:
    /// plain ⏎/click pastes the enhanced rewrite, ⌘⏎/⌘-click pastes the raw
    /// transcript (`commandHeld` == ⌘). All other commands ignore the modifier.
    private func run(_ cmd: PaletteCommand, commandHeld: Bool) {
        let target = capturedApp
        close()

        let action: () -> Void
        if let item = cmd.transcript {
            let text = CommandRegistry.transcriptPasteText(
                item: item,
                useEnhanced: CommandRegistry.transcriptUseEnhanced(commandHeld: commandHeld)
            )
            action = { CursorPaster.pasteAtCursor(text) }
        } else {
            action = cmd.run
        }

        if cmd.requiresFocusRestore, let target {
            // Re-focus the captured app, then run after it regains front.
            // The action itself pastes.
            target.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { action() }
        } else {
            action()
        }
    }

    private func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        capturedApp = nil
    }
}

/// A borderless `.nonactivatingPanel` won't become key by default, so the search
/// field couldn't receive typing. Overriding `canBecomeKey` lets the panel key
/// WITHOUT `NSApp.activate` — Sotto never comes forward, so the user's target app
/// stays frontmost. `canBecomeMain` stays false so it never becomes the main app
/// window.
private final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
