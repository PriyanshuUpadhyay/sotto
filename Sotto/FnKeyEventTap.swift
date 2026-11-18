import AppKit
import CoreGraphics
import os

private let logger = Logger(subsystem: OSLogSubsystems.app, category: "FnKeyEventTap")

/// Active event tap that takes Fn (🌐) presses away from macOS while Fn is
/// Sotto's shortcut, so the system "Press 🌐 key to" action (emoji picker,
/// input source, Dictation) does not also fire and steal the paste. Wispr Flow
/// documents the same behavior for a standalone Fn binding.
///
/// Only the Fn `flagsChanged` events are dropped. Fn+key chords still work,
/// because the Fn flag rides on the other key's own events.
///
/// The tap runs on its own thread: macOS waits for a tap's answer before it
/// delivers each event, so a tap on a busy main thread would slow all typing
/// and get disabled by timeout.
final class FnKeyEventTap {
    static let fnKeyCode: Int64 = 0x3F

    /// Called on the main queue with each Fn event the tap took.
    private let onFnEvent: (NSEvent) -> Void
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    init(onFnEvent: @escaping (NSEvent) -> Void) {
        self.onFnEvent = onFnEvent
    }

    deinit { stop() }

    static func shouldTake(type: CGEventType, keyCode: Int64) -> Bool {
        type == .flagsChanged && keyCode == fnKeyCode
    }

    /// Creates the tap. Returns false when macOS refuses it, usually because
    /// Accessibility is not granted yet.
    func start() -> Bool {
        guard port == nil else { return true }
        let ready = DispatchSemaphore(value: 0)
        var started = false
        let thread = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            started = self.install()
            ready.signal()
            if started { CFRunLoopRun() }
        }
        thread.name = "com.sotto.Sotto.fn-event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        if started { self.thread = thread }
        return started
    }

    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
        port = nil
        runLoop = nil
        thread = nil
    }

    /// Runs on the tap thread.
    private func install() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<FnKeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return false
        }
        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.runLoop = runLoop
        return true
    }

    /// Runs on the tap thread for every modifier change, so keep it short.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.error("fn tap: disabled by macOS (\(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public)) — enabling again")
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard Self.shouldTake(type: type, keyCode: keyCode),
              let copy = event.copy(),
              let nsEvent = NSEvent(cgEvent: copy) else {
            return Unmanaged.passUnretained(event)
        }
        DispatchQueue.main.async { [onFnEvent] in onFnEvent(nsEvent) }
        return nil
    }
}
