import Foundation
import KeyboardShortcuts
import Carbon
import AppKit
import os

extension KeyboardShortcuts.Name {
    static let toggleMiniRecorder = Self("toggleMiniRecorder")
    /// Single "Paste" shortcut — pastes the produced text (enhanced if present,
    /// else raw) via `LastTranscriptionService.pasteLastEnhancement`.
    static let pasteLastEnhancement = Self("pasteLastEnhancement")
    static let retryLastTranscription = Self("retryLastTranscription")
    static let openHistoryWindow = Self("openHistoryWindow")
    static let quickAddToDictionary = Self("quickAddToDictionary")

    /// ⌘K command palette — global summon. UNBOUND by default (no `default:`),
    /// so it never intercepts ⌘K system-wide until the user binds it in
    /// Settings → Shortcuts. The app-focused ⌘K lives on the main window scene.
    static let commandPalette = Self("commandPalette")
}

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

@MainActor
class HotkeyManager: ObservableObject {
    @Published var selectedHotkey1: HotkeyOption {
        didSet {
            UserDefaults.standard.set(selectedHotkey1.rawValue, forKey: "selectedHotkey1")
            setupHotkeyMonitoring()
        }
    }
    @Published var hotkeyMode1: HotkeyMode {
        didSet {
            UserDefaults.standard.set(hotkeyMode1.rawValue, forKey: "hotkeyMode1")
        }
    }

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "HotkeyManager")
    private var engine: SottoEngine
    private var recorderUIManager: RecorderUIManager
    private var miniRecorderShortcutManager: MiniRecorderShortcutManager

    // MARK: - Helper Properties
    private var canProcessHotkeyAction: Bool {
        engine.recordingState != .transcribing && engine.recordingState != .enhancing && engine.recordingState != .busy
    }
    
    // NSEvent monitoring for modifier keys
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    // Key state tracking
    private var currentKeyState = false
    private var keyPressEventTime: TimeInterval?
    private var isHandsFreeMode = false

    // Debounce for Fn key
    private var fnDebounceTask: Task<Void, Never>?
    private var pendingFnKeyState: Bool? = nil
    private var pendingFnEventTime: TimeInterval? = nil

    // Fn chord guard (Toggle mode): monitors live only while Fn is held.
    private var fnTapTracker = FnTapTracker()
    private var chordGlobalMonitor: Any?
    private var chordLocalMonitor: Any?

    // Keyboard shortcut state tracking
    private var shortcutKeyPressEventTime: TimeInterval?
    private var isShortcutHandsFreeMode = false
    private var shortcutCurrentKeyState = false
    private var lastShortcutTriggerTime: Date?
    private let shortcutCooldownInterval: TimeInterval = 0.5

    private static let hybridPressThreshold: TimeInterval = 0.5

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
    
    init(engine: SottoEngine, recorderUIManager: RecorderUIManager) {
        self.selectedHotkey1 = HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey1") ?? "") ?? .rightCommand

        self.hotkeyMode1 = HotkeyMode(rawValue: UserDefaults.standard.string(forKey: "hotkeyMode1") ?? "") ?? .hybrid

        self.engine = engine
        self.recorderUIManager = recorderUIManager
        self.miniRecorderShortcutManager = MiniRecorderShortcutManager(engine: engine, recorderUIManager: recorderUIManager)

        // Headless test guard: never register global hotkeys or event monitors
        // under XCTest — they would hijack the user's keyboard system-wide while
        // tests run. All stored properties are initialized above, so returning
        // here leaves a fully-constructed (but inert) manager.
        guard !AppRuntimeMode.isHeadlessTest else { return }

        KeyboardShortcuts.onKeyUp(for: .pasteLastEnhancement) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.pasteLastEnhancement(from: self.engine.modelContext)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .retryLastTranscription) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.retryLastTranscription(
                    from: self.engine.modelContext,
                    transcriptionModelManager: self.engine.transcriptionModelManager,
                    serviceRegistry: self.engine.serviceRegistry,
                    enhancementService: self.engine.enhancementService
                )
            }
        }

        KeyboardShortcuts.onKeyUp(for: .openHistoryWindow) {
            Task { @MainActor in
                SottoWindowCoordinator.shared.open(tab: .history)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .commandPalette) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                CommandPaletteController.shared.toggle(engine: self.engine)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .quickAddToDictionary) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                DictionaryQuickAddManager.shared.toggle(modelContainer: self.engine.modelContext.container)
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.setupHotkeyMonitoring()
        }
    }
    
    private func setupHotkeyMonitoring() {
        removeAllMonitoring()

        setupModifierKeyMonitoring()
        setupCustomShortcutMonitoring()
    }

    private func setupModifierKeyMonitoring() {
        // Only set up if the hotkey is a modifier key
        guard selectedHotkey1.isModifierKey && selectedHotkey1 != .none else { return }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleModifierKeyEvent(event)
            }
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            Task { @MainActor in
                await self.handleModifierKeyEvent(event)
            }
            return event
        }
    }
    
    private func setupCustomShortcutMonitoring() {
        if selectedHotkey1 == .custom {
            KeyboardShortcuts.onKeyDown(for: .toggleMiniRecorder) { [weak self] in
                let eventTime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in await self?.handleCustomShortcutKeyDown(eventTime: eventTime, mode: self?.hotkeyMode1 ?? .toggle) }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleMiniRecorder) { [weak self] in
                let eventTime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in await self?.handleCustomShortcutKeyUp(eventTime: eventTime, mode: self?.hotkeyMode1 ?? .toggle) }
            }
        }
    }

    private func removeAllMonitoring() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }

        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }

        removeChordMonitors()
        _ = fnTapTracker.fnUp()

        resetKeyStates()
    }

    private func installChordMonitors() {
        guard chordGlobalMonitor == nil, chordLocalMonitor == nil else { return }
        // .systemDefined included so Fn+media-keys (volume, brightness) count
        // as chords — they never arrive as .keyDown.
        let mask: NSEvent.EventTypeMask = [.keyDown, .systemDefined]
        chordGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in self?.fnTapTracker.otherKeyDown() }
        }
        chordLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.fnTapTracker.otherKeyDown() }
            return event
        }
    }

    private func removeChordMonitors() {
        if let monitor = chordGlobalMonitor { NSEvent.removeMonitor(monitor); chordGlobalMonitor = nil }
        if let monitor = chordLocalMonitor { NSEvent.removeMonitor(monitor); chordLocalMonitor = nil }
    }

    private func handleFnToggleRelease() async {
        removeChordMonitors()
        guard fnTapTracker.fnUp() else {
            logger.notice("fn release: chord detected — toggle suppressed")
            return
        }
        guard canProcessHotkeyAction else { return }
        markFirstHotkeyInvocation()
        logger.notice("fn tap: toggling mini recorder")
        await recorderUIManager.toggleMiniRecorder()
    }
    
    private func resetKeyStates() {
        currentKeyState = false
        keyPressEventTime = nil
        isHandsFreeMode = false
        shortcutCurrentKeyState = false
        shortcutKeyPressEventTime = nil
        isShortcutHandsFreeMode = false
    }
    
    private func handleModifierKeyEvent(_ event: NSEvent) async {
        let keycode = event.keyCode
        let flags = event.modifierFlags
        let eventTime = event.timestamp

        let activeMode: HotkeyMode
        let activeHotkey: HotkeyOption?
        if selectedHotkey1.isModifierKey && selectedHotkey1.keyCode == keycode {
            activeHotkey = selectedHotkey1
            activeMode = hotkeyMode1
        } else {
            activeHotkey = nil
            activeMode = .toggle
        }

        guard let hotkey = activeHotkey else { return }

        var isKeyPressed = false

        switch hotkey {
        case .rightOption, .leftOption:
            isKeyPressed = flags.contains(.option)
        case .leftControl, .rightControl:
            isKeyPressed = flags.contains(.control)
        case .fn:
            isKeyPressed = flags.contains(.function)
            // Process key DOWN immediately so quick taps (<75ms) aren't dropped.
            // Only debounce key UP to filter spurious flag-changed blips that macOS
            // emits during a held Fn key (Globe/Dictation disambiguation).
            pendingFnKeyState = isKeyPressed
            pendingFnEventTime = eventTime
            fnDebounceTask?.cancel()
            if activeMode == .toggle {
                // Chord guard: act on key-UP so Fn held as a modifier (Fn+F12)
                // never toggles recording. Hybrid/PTT keep key-down semantics.
                if isKeyPressed {
                    fnTapTracker.fnDown()
                    installChordMonitors()
                } else {
                    fnDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 75_000_000) // 75ms
                        guard !Task.isCancelled, pendingFnKeyState == false else { return }
                        Task { @MainActor in
                            await self.handleFnToggleRelease()
                        }
                    }
                }
                return
            }
            if isKeyPressed {
                await processKeyPress(isKeyPressed: true, eventTime: eventTime, mode: activeMode)
            } else {
                fnDebounceTask = Task { [pendingTime = eventTime] in
                    try? await Task.sleep(nanoseconds: 75_000_000) // 75ms
                    guard !Task.isCancelled, pendingFnKeyState == false else { return }
                    Task { @MainActor in
                        await self.processKeyPress(isKeyPressed: false, eventTime: pendingTime, mode: activeMode)
                    }
                }
            }
            return
        case .rightCommand:
            isKeyPressed = flags.contains(.command)
        case .rightShift:
            isKeyPressed = flags.contains(.shift)
        case .custom, .none:
            return // Should not reach here
        }

        await processKeyPress(isKeyPressed: isKeyPressed, eventTime: eventTime, mode: activeMode)
    }

    private func processKeyPress(isKeyPressed: Bool, eventTime: TimeInterval, mode: HotkeyMode) async {
        guard isKeyPressed != currentKeyState else { return }

        currentKeyState = isKeyPressed

        if isKeyPressed {
            keyPressEventTime = eventTime
            markFirstHotkeyInvocation()

            switch mode {
            case .toggle, .hybrid:
                if isHandsFreeMode {
                    isHandsFreeMode = false
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: toggling mini recorder (hands-free toggle)")
                    await recorderUIManager.toggleMiniRecorder()
                    return
                }

                if !recorderUIManager.isMiniRecorderVisible {
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: toggling mini recorder (key down while not visible)")
                    await recorderUIManager.toggleMiniRecorder()
                }

            case .pushToTalk:
                if !recorderUIManager.isMiniRecorderVisible {
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: starting recording (push-to-talk key down)")
                    await recorderUIManager.toggleMiniRecorder()
                }
            }
        } else {
            switch mode {
            case .toggle:
                isHandsFreeMode = true

            case .pushToTalk:
                if recorderUIManager.isMiniRecorderVisible {
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: stopping recording (push-to-talk key up)")
                    await recorderUIManager.toggleMiniRecorder()
                }

            case .hybrid:
                let pressDuration = keyPressEventTime.map { eventTime - $0 } ?? 0
                if pressDuration >= Self.hybridPressThreshold && engine.recordingState == .recording {
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: stopping recording (hybrid push-to-talk, duration=\(pressDuration, privacy: .public)s)")
                    await recorderUIManager.toggleMiniRecorder()
                } else {
                    isHandsFreeMode = true
                }
            }

            keyPressEventTime = nil
        }
    }
    
    private func handleCustomShortcutKeyDown(eventTime: TimeInterval, mode: HotkeyMode) async {
        if let lastTrigger = lastShortcutTriggerTime,
           Date().timeIntervalSince(lastTrigger) < shortcutCooldownInterval {
            return
        }

        guard !shortcutCurrentKeyState else { return }

        shortcutCurrentKeyState = true
        lastShortcutTriggerTime = Date()
        shortcutKeyPressEventTime = eventTime
        markFirstHotkeyInvocation()

        switch mode {
        case .toggle, .hybrid:
            if isShortcutHandsFreeMode {
                isShortcutHandsFreeMode = false
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyDown: toggling mini recorder (hands-free toggle)")
                await recorderUIManager.toggleMiniRecorder()
                return
            }

            if !recorderUIManager.isMiniRecorderVisible {
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyDown: toggling mini recorder (key down while not visible)")
                await recorderUIManager.toggleMiniRecorder()
            }

        case .pushToTalk:
            if !recorderUIManager.isMiniRecorderVisible {
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyDown: starting recording (push-to-talk key down)")
                await recorderUIManager.toggleMiniRecorder()
            }
        }
    }

    private func handleCustomShortcutKeyUp(eventTime: TimeInterval, mode: HotkeyMode) async {
        guard shortcutCurrentKeyState else { return }
        shortcutCurrentKeyState = false

        switch mode {
        case .toggle:
            isShortcutHandsFreeMode = true

        case .pushToTalk:
            if recorderUIManager.isMiniRecorderVisible {
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyUp: stopping recording (push-to-talk key up)")
                await recorderUIManager.toggleMiniRecorder()
            }

        case .hybrid:
            let pressDuration = shortcutKeyPressEventTime.map { eventTime - $0 } ?? 0
            if pressDuration >= Self.hybridPressThreshold && engine.recordingState == .recording {
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyUp: stopping recording (hybrid push-to-talk, duration=\(pressDuration, privacy: .public)s)")
                await recorderUIManager.toggleMiniRecorder()
            } else {
                isShortcutHandsFreeMode = true
            }
        }

        shortcutKeyPressEventTime = nil
    }
    
    // Computed property for backward compatibility with UI
    var isShortcutConfigured: Bool {
        (selectedHotkey1 == .custom) ? (KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) != nil) : true
    }

    func updateShortcutStatus() {
        // Called when a custom shortcut changes
        if selectedHotkey1 == .custom {
            setupHotkeyMonitoring()
        }
    }

    private func markFirstHotkeyInvocation() {
        guard !OnboardingState.shared.firstInvocationDidFire else { return }
        OnboardingState.shared.markFirstInvocation()
        NotificationCenter.default.post(name: .firstInvocationDidFire, object: nil)
    }

    deinit {
        Task { @MainActor in
            removeAllMonitoring()
        }
    }
}
