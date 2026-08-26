import Cocoa
import SwiftUI
import OSLog
import AVFoundation

/// Single source of truth for "running under a headless test harness".
/// When true, the app must NOT steal focus, show windows, present onboarding,
/// or register global hotkeys — so `xcodebuild test` runs without taking over
/// the user's screen. Driven by `SOTTO_HEADLESS_TESTS=1` (set on the mission
/// test command), with XCTest auto-detection as a belt-and-suspenders so even a
/// plain `xcodebuild test` stays headless.
enum AppRuntimeMode {
    static let isHeadlessTest: Bool = {
        if ProcessInfo.processInfo.environment["SOTTO_HEADLESS_TESTS"] == "1" { return true }
        return NSClassFromString("XCTestCase") != nil
    }()
}

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var menuBarManager: MenuBarManager?

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "AppDelegate")

    /// Engine-state → menu bar icon bridge. Lifetime tracks the app process
    /// (AppDelegate is retained for the duration). Bound to the engine in
    /// `SottoApp.init` after the engine finishes constructing.
    let recordingStateObserver = RecordingStateObserver()

    /// Headless guard: an app launched as an XCTest host must never become
    /// active or show windows frontmost. `.prohibited` makes that structural —
    /// the app cannot activate, so no test run can yank the user's focus.
    func applicationWillFinishLaunching(_ notification: Notification) {
        if AppRuntimeMode.isHeadlessTest {
            NSApp.setActivationPolicy(.prohibited)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppRuntimeMode.isHeadlessTest else { return }
        guard PlatformSupport.launchOutcome() == .opensMenuBarItem else {
            reportUnsupportedMacOSVersion()
            return
        }
        warnIfDuplicateInstanceRunning()
        menuBarManager?.applyActivationPolicy()
        surfaceWindowOnUserLaunch(notification)
        requestMissingPermissionsOnLaunch()
    }

    /// macOS older than `PlatformSupport.minimumMacOS` cannot run Sotto — the
    /// menu bar item never appears, so say why and quit instead of leaving a
    /// half-started process behind.
    private func reportUnsupportedMacOSVersion() {
        logger.error("Unsupported macOS version; Sotto needs \(PlatformSupport.minimumMacOSDisplayString, privacy: .public)")
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Unsupported macOS version"
        alert.informativeText = PlatformSupport.unsupportedVersionMessage
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    /// Re-prompt for any permission Sotto still lacks, once per launch. Onboarding
    /// owns first-run prompting, so this only runs after it completes. Microphone
    /// is prompted only while `.notDetermined` — a `.denied` mic can't be re-shown
    /// by macOS, and re-asking is what the user's explicit denial rules out.
    /// Accessibility and Screen Recording re-prompt every launch until granted.
    /// Deferred one runloop turn so dialogs don't fire before the run loop settles.
    private func requestMissingPermissionsOnLaunch() {
        guard UserDefaults.standard.bool(forKey: OnboardingState.Key.completed) else { return }
        DispatchQueue.main.async {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            }
            let axOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(axOptions)
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
        }
    }

    /// Cold-launch window surfacing. Sotto is menu-bar-primary and its
    /// `WindowGroup` is `.defaultLaunchBehavior(.suppressed)`, so a fresh launch
    /// shows only the menu-bar icon — from the user's POV "opening Sotto did
    /// nothing" (Raycast / Finder / `open -a` while not already running). Surface
    /// the main window on a user-initiated launch via the canonical coordinator.
    ///
    /// Skipped when it's a login-item launch (reported as non-default), so a
    /// launch-at-login start stays quiet in the menu bar.
    private func surfaceWindowOnUserLaunch(_ notification: Notification) {
        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) ?? true
        logger.notice("applicationDidFinishLaunching: isDefaultLaunch=\(isDefaultLaunch, privacy: .public)")
        guard isDefaultLaunch else { return }
        // Defer one runloop turn so the MenuBarExtra label's onAppear has
        // registered the window opener with SottoWindowCoordinator.
        DispatchQueue.main.async {
            SottoWindowCoordinator.shared.open(tab: .history)
        }
    }

    /// Surface a duplicate-instance launch. Two processes sharing
    /// `com.sotto.Sotto` register the same global ESC hotkey via
    /// per-process Carbon while sharing UserDefaults — when one deactivates
    /// on recorder-hide, the other's registration survives and intercepts
    /// system-wide ESC. Notify, don't auto-quit: a deliberate `.local-build`
    /// dev launch alongside `/Applications/Sotto.app` is legitimate.
    private func warnIfDuplicateInstanceRunning() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let self_pid = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != self_pid }
        guard !others.isEmpty else { return }

        let paths = others.compactMap { $0.bundleURL?.path }.joined(separator: ", ")
        let pids = others.map { String($0.processIdentifier) }.joined(separator: ",")
        logger.warning("⚠️ Another Sotto instance is running (pids=\(pids, privacy: .public), paths=\(paths, privacy: .public)) — global shortcuts may misbehave")
        Task { @MainActor in
            NotificationManager.shared.showNotification(
                title: "Another Sotto is running — global shortcuts may misbehave",
                type: .warning,
                duration: 6.0
            )
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Re-open with no visible window (Dock click, `open -a`, Raycast):
            // surface the on-demand Sotto window via the canonical coordinator.
            // This must fire even in menu-bar-only mode — the window is fully
            // usable there; `.open` flips the policy to .regular and activates,
            // and closing it returns the app to .accessory (MenuBarManager).
            // The earlier `!isMenuBarOnly` guard made re-open a silent no-op for
            // exactly the users who hide the Dock icon.
            SottoWindowCoordinator.shared.open(tab: .history)
            return false
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

