import AppKit
import Combine
import Foundation

// MARK: - CursorProximityMonitor
//
// Tracks cursor distance to the menu bar baseline. Drives `WhisperLine`
// opacity attenuation so the idle whisper brightens as the user approaches
// the menu bar and disappears when they're focused elsewhere.
//
// Spec refs: §3.1 (Idle / Whisper hover-aware behavior), §6.6 (cursor
// monitor power cost).
//
// Distance ramp (pt, all measured from cursor → top of screen-containing-cursor):
//   - `> 200pt`        → `proximity = 0`
//   - `60..200pt`      → linear `(200 - d) / 140`  →  `d=130` ≈ `0.5`
//   - `≤ 60pt`         → `proximity = 1`
//
// 30Hz coalescing throttle (~33ms): events arriving inside the window are
// dropped. No per-event Timer spawn (plan §P1.H risk note). Mouse-moved
// events fire at 60–100Hz natively; halving the rate keeps the monitor under
// 1% CPU per the spec §6.6 power-cost target.
//
// Background pause (spec §6.6): on `NSApplication.didResignActiveNotification`
// the global event monitor is removed and `proximity` is reset to 0
// (verification: `print` in the proximity setter emits NO output while the
// app is inactive). On `didBecomeActiveNotification` the monitor is
// re-attached and we resample once.
//
// Multi-display correctness (plan reviewer focus): distance is measured
// against the screen *containing the cursor*, not `NSScreen.main`. macOS
// puts a menu bar at the top of every screen; the geometry answer for
// distance to "the menu bar" is the distance to the top of whichever screen
// the cursor lives on. Using `.main` would give wrong numbers as soon as
// the user moves the cursor onto a secondary display.
//
// Permissions: `addGlobalMonitorForEvents(matching: .mouseMoved)` does NOT
// require Accessibility permissions — only key-event monitoring does
// (`.keyDown`, `.keyUp`, `.flagsChanged`). Mouse-event monitors run with
// no entitlement.

final class CursorProximityMonitor: ObservableObject {
    /// 0…1 normalized cursor proximity to the menu bar of the screen
    /// containing the cursor. `private(set)` so only the monitor mutates it;
    /// callers `@ObservedObject` and read.
    @Published private(set) var proximity: Double = 0

    // MARK: Internal state

    private var monitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var becomeActiveObserver: NSObjectProtocol?

    /// Coalescing throttle window. ~33ms = 30Hz.
    private static let throttleInterval: TimeInterval = 1.0 / 30.0
    private var lastEmit: Date = .distantPast

    // MARK: Spec ramp constants (pt) — see ramp table at file head.
    private static let nearThreshold: CGFloat = 60
    private static let farThreshold:  CGFloat = 200

    // MARK: - Lifecycle

    init() {
        let center = NotificationCenter.default
        resignActiveObserver = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pause()
        }
        becomeActiveObserver = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resume()
        }

        // Start active iff the app is currently frontmost. If launched in
        // background (login item), monitor stays paused until activation.
        if NSApplication.shared.isActive {
            resume()
        }
    }

    deinit {
        teardownMonitor()
        let center = NotificationCenter.default
        if let obs = resignActiveObserver { center.removeObserver(obs) }
        if let obs = becomeActiveObserver { center.removeObserver(obs) }
    }

    // MARK: - Pause / resume gating

    private func resume() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleMouseMoved()
        }
        // Initial sample so the line lights up immediately on app activate
        // — without it `proximity` stays at its last value (or 0 from
        // `pause()`) until the user nudges the mouse.
        sample(force: true)
    }

    private func pause() {
        teardownMonitor()
        // Clear proximity so a stale "near" reading doesn't keep WhisperLine
        // bright while events are paused.
        if proximity != 0 { proximity = 0 }
    }

    private func teardownMonitor() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    // MARK: - Throttle + sample

    private func handleMouseMoved() {
        let now = Date()
        guard now.timeIntervalSince(lastEmit) >= Self.throttleInterval else { return }
        lastEmit = now
        sample(force: false)
    }

    private func sample(force: Bool) {
        // Belt + suspenders: `pause()` already removes the monitor, but if a
        // queued handler fires after the resign-active notification we still
        // want to drop it.
        guard force || NSApplication.shared.isActive else { return }
        let next = computeProximity()
        if next != proximity { proximity = next }
    }

    // MARK: - Geometry

    /// Distance from cursor to the top edge of the screen containing the
    /// cursor. `NSEvent.mouseLocation` and `NSScreen.frame` share the same
    /// global coord system (origin at bottom-left of the primary screen,
    /// y-up). The menu bar baseline of any given screen is at that screen's
    /// `frame.maxY`, so:
    ///
    ///   distance_pt = screen.frame.maxY - cursor.y
    ///
    /// This is the same formula on the primary and on any secondary display
    /// regardless of the secondary's position relative to the primary.
    private func computeProximity() -> Double {
        let cursor = NSEvent.mouseLocation
        guard let screen = screenContaining(point: cursor) else { return 0 }
        let distance = screen.frame.maxY - cursor.y
        return Self.proximity(forDistance: distance)
    }

    private func screenContaining(point: CGPoint) -> NSScreen? {
        // Cursor should always lie within some screen, but during rapid
        // display reconfiguration there can be a one-event window where it
        // doesn't — fall back to `.main` rather than crashing. (Returning 0
        // proximity is the safe behavior for that frame.)
        if let s = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return s
        }
        return NSScreen.main
    }

    /// Pure ramp — extracted so it's trivially unit-testable and so the
    /// reviewer can confirm the spec ramp endpoints (200→0, 130→0.5, 60→1)
    /// without spinning up an event monitor.
    static func proximity(forDistance distance: CGFloat) -> Double {
        if distance <= nearThreshold { return 1.0 }
        if distance >= farThreshold  { return 0.0 }
        let span = farThreshold - nearThreshold        // 140pt
        let t = (farThreshold - distance) / span
        return Double(t)
    }
}
