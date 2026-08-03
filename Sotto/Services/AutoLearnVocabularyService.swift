import Foundation
import AppKit
import SwiftData
import ApplicationServices
import NaturalLanguage
import os

final class AutoLearnVocabularyService {
    static let shared = AutoLearnVocabularyService()
    private init() {}

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "AutoLearnVocabulary")

    // Active monitoring state
    private var pastedText: String = ""
    private var lastKnownText: String = ""
    private var modelContext: ModelContext?
    private var timeoutTimer: DispatchSourceTimer?
    private var axObserver: AXObserver?
    // The element being monitored — retained so finalize() can re-read its value
    // directly rather than trusting the (possibly never-fired) observer callback.
    private var monitoredElement: AXUIElement?
    private var workspaceObserver: NSObjectProtocol?
    private var isActive = false

    // Pending state — set during paste, activated after recorder dismisses
    private var pendingElement: AXUIElement?
    private var pendingText: String = ""
    private var pendingContext: ModelContext?

    // Must be called before paste fires, while the target text field still has focus
    func captureFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else { return nil }
        return (focusedElement as! AXUIElement)
    }

    // Step 1: Called during paste — stores state but does NOT start observers yet
    func prepareMonitoring(pastedText: String, element: AXUIElement, modelContext: ModelContext) {
        pendingElement = element
        pendingText = pastedText
        pendingContext = modelContext
        // Electron/Chromium apps present an EMPTY accessibility tree until an
        // assistive client signals interest, so their text field reads back as
        // "" — making edits in Slack/Discord/VS Code/Notion invisible. Setting
        // AXManualAccessibility on the app element materializes the tree without
        // the window-positioning side effect AXEnhancedUserInterface causes. The
        // tree builds async (~200ms); harmless on non-Electron apps (returns
        // unsupported). Done here at paste time so the finalize-time read sees it.
        enableManualAccessibilityIfNeeded(for: element)
    }

    // Best-effort: unblock Electron/Chromium empty-AX-tree inputs so their value
    // is readable on demand. No-op / unsupported on native apps — result ignored.
    private func enableManualAccessibilityIfNeeded(for element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // Step 2: Called after recorder dismisses — now safe to start observing
    func beginMonitoring() {
        guard UserDefaults.standard.object(forKey: "autoLearnVocabulary") as? Bool ?? true else { return }
        guard let element = pendingElement, let context = pendingContext else {
            // Dogfood diagnostic: a silent capture-miss here (prepareMonitoring
            // never ran before this, e.g. paste closure hadn't fired) would look
            // like "feature broken" — no vocab learned — at the gate. Log it so
            // the miss is distinguishable from "no edits made".
            logger.notice("🧠 auto-vocab: beginMonitoring no-op (no pending element — capture not armed)")
            return
        }
        let pasted = pendingText
        pendingElement = nil
        pendingContext = nil
        pendingText = ""

        startMonitoring(pastedText: pasted, element: element, modelContext: context)
    }

    private func startMonitoring(pastedText: String, element: AXUIElement, modelContext: ModelContext) {
        stopMonitoring()

        self.pastedText = pastedText
        self.lastKnownText = pastedText
        self.monitoredElement = element
        self.modelContext = modelContext
        self.isActive = true

        setupValueChangeObserver(for: element)
        setupAppSwitchObserver()
        startTimeoutTimer()
    }

    func stopMonitoring() {
        isActive = false

        timeoutTimer?.cancel()
        timeoutTimer = nil

        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            axObserver = nil
        }

        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }

        monitoredElement = nil
        modelContext = nil
    }

    // Direct read of the monitored element's current value. Returns nil when the
    // element is gone (kAXErrorInvalidUIElement after the field/tab/view was
    // destroyed) or yields no string — caller then falls back to the cached text.
    private func readMonitoredValue() -> String? {
        guard let element = monitoredElement else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        return text
    }

    // Watch the specific element for value changes — cache latest text on every keystroke.
    //
    // This observer is the cheap fast-path for apps that emit
    // kAXValueChangedNotification (AppKit/Cocoa fields, most web inputs). Apps that
    // DON'T emit it are no longer fully blind: finalize() re-reads the element's
    // value directly (readMonitoredValue), so any surface whose value is readable
    // on demand is now captured even with no notification.
    //
    // STILL UNREACHABLE: terminal/TUI surfaces — cmux (com.cmuxterm.app), iTerm,
    // Terminal — clear the input line on Enter (send), so a finalize-time read
    // after submit sees an empty line. Capturing those needs an Enter-time event
    // tap / keystroke reconstruction (CGEventTap + Input Monitoring); out of scope
    // for this tier (see edit-learning spec).
    private func setupValueChangeObserver(for element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            logger.notice("⚠️ Could not get PID from element — skipping value observer")
            return
        }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, changedElement, _, refcon in
            guard let refcon else { return }
            let service = Unmanaged<AutoLearnVocabularyService>.fromOpaque(refcon).takeUnretainedValue()
            guard service.isActive else { return }
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(changedElement, kAXValueAttribute as CFString, &value) == .success,
               let text = value as? String {
                service.lastKnownText = text
            }
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let obs = observer else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(obs, element, kAXValueChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        axObserver = obs
    }

    // Finalize immediately when user switches to a different app
    private func setupAppSwitchObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            self.finalize()
        }
    }

    private func startTimeoutTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30)
        timer.setEventHandler { [weak self] in
            guard let self, self.isActive else { return }
            self.finalize()
        }
        timer.resume()
        timeoutTimer = timer
    }

    // Called on main queue — from app switch or timeout
    private func finalize() {
        guard isActive else { return }
        isActive = false

        timeoutTimer?.cancel()
        timeoutTimer = nil

        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            axObserver = nil
        }

        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }

        guard let context = modelContext else { return }
        modelContext = nil

        // Re-read the field value directly rather than trusting the observer's
        // cached text. Notification support and read support are INDEPENDENT: many
        // surfaces never emit kAXValueChangedNotification (so lastKnownText is
        // stale at the pasted text) yet still return their current value on demand.
        // A fresh read recovers edits in those apps; fall back to the observer
        // cache when the element is gone/unreadable (kAXErrorInvalidUIElement).
        let currentText = readMonitoredValue() ?? lastKnownText
        monitoredElement = nil
        let baseline = pastedText

        guard currentText != baseline else { return }

        // Strict 1:1 alignment only. `WordDiffEngine.findSingleWordSubstitutions`
        // emits the CROSS-PRODUCT of an unequal-length changed span's tokens, so
        // a phrase rewrite — or a phantom whole-field diff from an AX read-back
        // that never matched the pasted baseline — mints substitutions the user
        // never made (see `CorrectionMiner.alignedSubstitutions`). Accepted cost:
        // an equal-length multi-token fix ("jon smyth" → "John Smith", a
        // 2-delete/2-insert span) is dropped — only a single changed token, or a
        // merge the fragments literally spell, is certain enough to learn from.
        let allSubstitutions = CorrectionMiner.alignedSubstitutions(original: baseline, edited: currentText)
        // Those drops are otherwise invisible: report how many spans the edit
        // changed vs how many yielded a learnable pair.
        let changedSpans = WordDiffEngine.tokenLevelDiff(original: baseline, edited: currentText)
            .split(whereSeparator: { if case .equal = $0 { return true } else { return false } })
            .count
        logger.notice("🧠 auto-vocab: \(changedSpans, privacy: .public) changed spans, \(allSubstitutions.count, privacy: .public) mined")
        guard !allSubstitutions.isEmpty else { return }

        // Only consider corrections to words that were part of the pasted
        // transcript. A merged original is multi-word ("para keet"), so every
        // component must trace back to the paste, not the original as a whole.
        let pastedTokens = Set(pastedText.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
            .filter { !$0.isEmpty })

        let substitutions = allSubstitutions.filter { sub in
            let components = sub.original.components(separatedBy: .whitespaces)
                .map { $0.lowercased() }
                .filter { !$0.isEmpty }
            return !components.isEmpty && components.allSatisfy { pastedTokens.contains($0) }
        }
        guard !substitutions.isEmpty else { return }

        guard isSupportedLanguage(currentText) else { return }

        let namedEntities = namedEntitiesIn(currentText)

        var wordsToAdd = [String]()
        for (_, replWord) in substitutions {
            guard let correctedRange = currentText.range(of: replWord, options: .caseInsensitive) else { continue }
            let correctedPosition = currentText.distance(from: currentText.startIndex, to: correctedRange.lowerBound)

            let candidates = namedEntities.filter { entity in
                entity.name.components(separatedBy: .whitespaces)
                    .map { $0.lowercased() }
                    .contains(replWord.lowercased())
            }
            if let closest = candidates.min(by: { abs($0.position - correctedPosition) < abs($1.position - correctedPosition) }),
               Self.isLikelyProperTerm(closest.name) {
                wordsToAdd.append(closest.name)
            }
        }

        let uniqueWordsToAdd = Array(NSOrderedSet(array: wordsToAdd)) as! [String]
        guard !uniqueWordsToAdd.isEmpty else { return }

        // A single edit pass yielding this many new entities is a bogus surface
        // read-back (pre-existing field content diffed against the paste), not
        // user corrections — drop the batch rather than poison the vocabulary.
        guard uniqueWordsToAdd.count <= 3 else {
            logger.notice("⚠️ auto-vocab: dropping burst of \(uniqueWordsToAdd.count, privacy: .public) candidates — diff looks bogus")
            return
        }

        let descriptor = FetchDescriptor<VocabularyWord>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingWords = Set(existing.map { $0.word.lowercased() })

        var addedWords: [VocabularyWord] = []

        for word in uniqueWordsToAdd {
            guard !existingWords.contains(word.lowercased()) else {
                logger.notice("⚠️ \"\(word, privacy: .public)\" already in Vocabulary — skipping")
                continue
            }

            let newWord = VocabularyWord(word: word)
            context.insert(newWord)
            addedWords.append(newWord)
            logger.notice("✅ Added \"\(word, privacy: .public)\" to Vocabulary")
        }

        guard !addedWords.isEmpty else { return }
        try? context.save()

        let title: String
        if addedWords.count == 1 {
            title = "Added \"\(addedWords[0].word)\" to Vocabulary"
        } else {
            title = "Added \(addedWords.count) words to Vocabulary"
        }

        Task { @MainActor in
            NotificationManager.shared.showNotification(
                title: title,
                type: .success,
                duration: 4.0,
                actionButton: ("Undo", {
                    for word in addedWords {
                        context.delete(word)
                    }
                    try? context.save()
                })
            )
        }
    }

    /// OOV gate: a candidate is worth learning only if at least one of its
    /// whitespace-separated components is NOT a known dictionary word. NLTagger
    /// tags sentence-start capitalized common words ("No", "Same", "Filter") as
    /// named entities, and learning those actively biases the ASR wrong. The
    /// deliberate cost is that dictionary-word proper names ("Hunter") are no
    /// longer auto-learned — precision over recall.
    ///
    /// The component is LOWERCASED before the check: NSSpellChecker treats
    /// all-caps tokens as acronyms and never flags them (same caveat as
    /// `PhoneticCorrectionService`). `isMisspelled` is injected — defaulting to
    /// the OS spell checker — so tests don't depend on host dictionary state.
    static func isLikelyProperTerm(
        _ name: String,
        isMisspelled: (String) -> Bool = AutoLearnVocabularyService.osIsMisspelled
    ) -> Bool {
        let components = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !components.isEmpty else { return false }
        return components.contains { isMisspelled($0.lowercased()) }
    }

    /// OS spell-checker OOV probe — the production `isLikelyProperTerm` predicate.
    static func osIsMisspelled(_ word: String) -> Bool {
        let range = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0)
        return range.location != NSNotFound && range.length > 0
    }

    private static let nerSupportedLanguages: Set<NLLanguage> = [
        .english, .german, .french, .spanish, .italian, .portuguese, .russian, .turkish
    ]

    private func isSupportedLanguage(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return false }
        return Self.nerSupportedLanguages.contains(language)
    }

    private func namedEntitiesIn(_ text: String) -> [(name: String, position: Int)] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var entities = [(name: String, position: Int)]()
        let entityTags: Set<NLTag> = [.personalName, .placeName, .organizationName]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            if let tag, entityTags.contains(tag) {
                let position = text.distance(from: text.startIndex, to: range.lowerBound)
                entities.append((name: String(text[range]), position: position))
            }
            return true
        }
        return entities
    }
}
