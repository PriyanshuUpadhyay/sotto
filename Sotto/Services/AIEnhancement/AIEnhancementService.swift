import Foundation
import SwiftData
import AppKit
import os

/// Single-fire race-safe slot for the record-start selected-text capture.
/// The capture task calls `write` exactly once when its fetch resolves; each
/// reader calls `read` and gets the value immediately if already written, or
/// waits on ITS OWN continuation, resumed by whichever of `write` or ITS OWN
/// timeout fires first (resume-exactly-once per reader, enforced by removing
/// that reader's entry from `waiters` the instant either side consumes it).
/// Multiple concurrent readers are real (the live pipeline and a file/history
/// re-enhance can call `enhance(...)` around the same time) — a single shared
/// continuation slot would let a second `read()` silently orphan the first
/// reader's continuation, hanging it forever; keying by a per-call UUID keeps
/// every reader independent.
///
/// Deliberately NOT a `TaskGroup` race (`withTaskGroup`/`cancelAll`) — a group
/// only returns once EVERY child actually finishes, including a cancelled one
/// that isn't cooperatively checking `Task.isCancelled`, so a stuck fetch
/// would hang the whole group despite "losing" the race. Here the fetch task
/// is left to run to completion in the background; if it loses every race,
/// its eventual `write` just finds no waiters left and is a no-op.
actor SelectedTextSlot {
    private var value: String?
    private var isWritten = false
    private var waiters: [UUID: CheckedContinuation<String?, Never>] = [:]

    func write(_ newValue: String?) {
        guard !isWritten else { return }
        value = newValue
        isWritten = true
        let pending = waiters
        waiters = [:]
        for continuation in pending.values {
            continuation.resume(returning: newValue)
        }
    }

    func read(timeoutSeconds: TimeInterval, sleep: @escaping @Sendable (Duration) async -> Void) async -> String? {
        if isWritten { return value }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = continuation
            Task {
                await sleep(.seconds(timeoutSeconds))
                await self.resolveTimeout(id: id)
            }
        }
    }

    private func resolveTimeout(id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        continuation.resume(returning: nil)
    }
}

/// Single-path AI enhancement: Apple Foundation Models (AFM) running one fixed
/// "Light" cleanup prompt. Enhancement is a gated step in the core loop —
/// toggled ON it cleans the transcript via AFM, toggled OFF the raw transcript
/// passes through untouched. Provider selection, intensity levels, and the
/// custom-prompts system were all removed in the UX collapse.
@MainActor
class AIEnhancementService: ObservableObject {
    let logger = Logger(subsystem: OSLogSubsystems.app, category: "AIEnhancementService")

    /// On/off gate for enhancement. `.light` = enabled (the single fixed path),
    /// `.none` = disabled (raw transcript).
    @Published var enhanceLevel: EnhanceLevel {
        didSet {
            UserDefaults.standard.set(enhanceLevel.rawValue, forKey: "enhanceLevel")
            // Keep the legacy bool key in sync so a downgrade preserves on/off.
            UserDefaults.standard.set(enhanceLevel != .none, forKey: "isAIEnhancementEnabled")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .enhancementToggleChanged, object: nil)
        }
    }

    /// Plain on/off view over `enhanceLevel`. Enabling maps to the single
    /// `.light` path; disabling to `.none`.
    var isEnhancementEnabled: Bool {
        get { enhanceLevel != .none }
        set { enhanceLevel = newValue ? .light : .none }
    }

    @Published var useClipboardContext: Bool {
        didSet {
            UserDefaults.standard.set(useClipboardContext, forKey: "useClipboardContext")
        }
    }

    @Published var useScreenCaptureContext: Bool {
        didSet {
            UserDefaults.standard.set(useScreenCaptureContext, forKey: "useScreenCaptureContext")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    /// Show the post-paste feedback tray (revert-raw / wrong / edit) after an
    /// enhanced-and-changed paste. Default ON.
    @Published var showFeedbackTray: Bool {
        didSet { UserDefaults.standard.set(showFeedbackTray, forKey: "ShowFeedbackTray") }
    }

    @Published var lastSystemMessageSent: String?
    @Published var lastUserMessageSent: String?

    /// The model id that actually produced the last enhancement —
    /// "apple-on-device" for AFM, "deterministic-cleanup" when the repair guard
    /// fell back. Read by the pipeline so History records the real provider.
    @Published var lastEnhancementModelUsed: String?

    /// The raw first-pass enhancement output, BEFORE the repair guard ran.
    @Published var lastRawEnhancement: String?

    /// What the repair guard did on the most recent enhance.
    @Published var lastGuardOutcome: EnhancementGuardOutcome = .notRun

    let aiService: AIService
    let screenCaptureService: ScreenCaptureService
    let customVocabularyService: CustomVocabularyService
    let modelContext: ModelContext

    @Published var lastCapturedClipboard: String?

    var frontmostAppProvider: () -> (name: String, bundleID: String)? = {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let name = app.localizedName,
              let bundleID = app.bundleIdentifier else { return nil }
        return (name: name, bundleID: bundleID)
    }

    /// Overridable so tests can drive selected-text capture without real
    /// AX/menu-Copy access — same pattern as `frontmostAppProvider`.
    var selectedTextProvider: () async -> String? = {
        guard AXIsProcessTrusted() else { return nil }
        return await SelectedTextService.fetchSelectedText()
    }

    /// Waits out the `cachedSelectedText` grace period. Overridable so tests can
    /// fire or withhold the timeout without depending on wall-clock time.
    var selectedTextGraceSleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }

    /// Set once at record-start (`captureSelectedTextContext`) and read via
    /// `cachedSelectedText` at enhancement time — never fetched live on the
    /// post-ASR path (the AX/menu-Copy fallback costs 100s of ms, and the old
    /// live fetch ran twice: once for prewarm, once for the real enhance).
    var selectedTextSlot: SelectedTextSlot?

    /// Bumped at every record-start (`beginNewDictation`). Every record-start
    /// context write (selected text, clipboard, screen, active-app/vocab
    /// snapshot, AFM warm) is called with the generation that was current
    /// when its OWNING dictation started, and checks it against the CURRENT
    /// value before writing — a delayed write from a cancelled or superseded
    /// dictation can never land in a newer dictation's slot.
    private(set) var dictationGeneration = 0

    /// Frontmost-app / custom-vocabulary snapshot, captured ONCE at
    /// record-start (`captureDictationSnapshot`) and reused by both the
    /// record-start AFM warm and the real post-ASR enhance — see
    /// `getSystemInstructions`'s doc comment for why this must be byte-stable
    /// within a dictation. Tagged with its OWN generation (not read implicitly
    /// from `dictationGeneration`, which could differ by the time it's
    /// consumed) — see `currentDictationSnapshot`.
    struct DictationSnapshot {
        let generation: Int
        let activeApp: (name: String, bundleID: String)?
        let customVocabulary: String
    }
    var dictationSnapshot: DictationSnapshot?

    /// The snapshot IF it belongs to the CURRENT generation, else `nil`. This
    /// is deliberately a presence check, not `snapshot.activeApp ?? live` —
    /// a snapshot that legitimately captured "no active app" (the toggle is
    /// off, or `frontmostAppProvider` returned nil) must NOT fall back to a
    /// live read just because its `activeApp` happens to be nil; only the
    /// ABSENCE of a valid-for-this-generation snapshot (no record-start ever
    /// ran for this call) should fall back to live. Never consulted by the
    /// import path (`performEnhance(_:isImport: true)`) at all — that path
    /// always reads live directly, regardless of what this resolves to.
    private var currentDictationSnapshot: DictationSnapshot? {
        guard let snapshot = dictationSnapshot, snapshot.generation == dictationGeneration else { return nil }
        return snapshot
    }

    var resolvedActiveApp: (name: String, bundleID: String)? {
        if let snapshot = currentDictationSnapshot { return snapshot.activeApp }
        return activeAppForContext
    }

    var resolvedCustomVocabulary: String {
        if let snapshot = currentDictationSnapshot { return snapshot.customVocabulary }
        return customVocabularyService.getCustomVocabulary(from: modelContext)
    }

    /// Bumps and returns the dictation generation — call synchronously at
    /// record-start, before any async work, so the caller can thread the
    /// returned value through the whole record-start capture/warm chain.
    /// Clears any prior snapshot synchronously too (rather than relying on
    /// `captureDictationSnapshot` to overwrite it later — that call can be
    /// delayed or never happen at all, e.g. a very slow or crashed
    /// record-start task, and a stale snapshot must never be mistaken for
    /// this new dictation's). Also fires an unconditional AFM warm-slot reset
    /// (fire-and-forget, belt-and-suspenders on top of `AFMProvider`'s own
    /// generation-tagged consume check) so a stale warm can never survive
    /// into the new dictation even briefly.
    @discardableResult
    func beginNewDictation() -> Int {
        dictationGeneration += 1
        dictationSnapshot = nil
        Task { await aiService.resetAFMForNewDictation() }
        return dictationGeneration
    }

    init(aiService: AIService = AIService(), modelContext: ModelContext) {
        self.aiService = aiService
        self.modelContext = modelContext
        self.screenCaptureService = ScreenCaptureService()
        self.customVocabularyService = CustomVocabularyService.shared

        // Prefer the canonical enhanceLevel key (folding removed medium/high onto
        // light); fall back to the legacy bool key.
        if let raw = UserDefaults.standard.string(forKey: "enhanceLevel"),
           let level = EnhanceLevel.migrating(rawValue: raw) {
            self.enhanceLevel = level
        } else if UserDefaults.standard.object(forKey: "isAIEnhancementEnabled") != nil {
            self.enhanceLevel = .from(legacyBool: UserDefaults.standard.bool(forKey: "isAIEnhancementEnabled"))
        } else {
            self.enhanceLevel = .default
        }
        self.useClipboardContext = UserDefaults.standard.bool(forKey: "useClipboardContext")
        self.useScreenCaptureContext = UserDefaults.standard.bool(forKey: "useScreenCaptureContext")
        self.showFeedbackTray = UserDefaults.standard.object(forKey: "ShowFeedbackTray") as? Bool ?? true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChange),
            name: .aiProviderKeyChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAPIKeyChange() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            if !self.aiService.isAPIKeyValid {
                self.isEnhancementEnabled = false
            }
        }
    }

    func getAIService() -> AIService? {
        return aiService
    }

    /// Reads live AFM availability each access via a non-mutating probe (never
    /// `refreshAPIKeyValidity()`, which publishes `isAPIKeyValid` — mutating a
    /// `@Published` property from a getter invoked during SwiftUI body
    /// evaluation is undefined timing). A transient `.modelNotReady` at launch
    /// (Apple Intelligence still downloading) must not disable enhancement for
    /// the rest of the session once AFM becomes ready.
    var isConfigured: Bool {
        aiService.checkAvailabilityNow()
    }

    /// The frontmost app used to steer the prompt register and the deterministic
    /// mechanics post-pass — gated by the same privacy setting as the `<ACTIVE_APP>`
    /// context block, so both the directive and the post-pass see one source.
    var activeAppForContext: (name: String, bundleID: String)? {
        let useActiveAppContext = UserDefaults.standard.object(forKey: "useActiveAppContext") as? Bool ?? true
        return useActiveAppContext ? frontmostAppProvider() : nil
    }
}
