import SwiftUI
import AppKit
import Combine
import os

// MARK: - ComposeReviewWindowManager
//
// Review-before-paste: instead of detecting edits AFTER an auto-paste (which is
// unreliable in terminals / Electron apps), show the proposed text in an
// editable preview BEFORE pasting. The user reads it, optionally edits, then
// presses ⌘↵ to run the normal paste sequence — or Esc to cancel without
// pasting. The edit signal is then exact (the user's final text vs the
// enhanced text, captured in our own field — no AX, no diff inference).
//
// The panel is intentionally STATIC: screen-centred, NOT draggable. It is a KEY
// panel on show (the editor must receive typing), but `.nonactivatingPanel`
// keeps the user's app frontmost underneath, so on `orderOut` (⌘↵ / Esc) focus
// returns to the target field for the paste. Dismiss model is minimal: ONLY ⌘↵
// (commit) or Esc (cancel).
//
// Reuses `ReviewTrayPanel` (the nonactivating, full-screen-auxiliary NSPanel).
@MainActor
final class ComposeReviewWindowManager: NSObject, ObservableObject {
    static let shared = ComposeReviewWindowManager()

    /// Must match `ComposeReviewView.panelWidth`.
    private static let panelWidth: CGFloat = 460
    private static let defaultHeight: CGFloat = 260

    /// Which face of the transcript the editor shows (and what ⌘↵ pastes).
    /// `.draft` is the user's raw-lineage edited text — a segment of its own
    /// that appears ONLY when their edits deferred an enhanced delivery
    /// (RAW must always stay the pristine as-heard reference). It is also the
    /// internal face while enhancing / without enhancement, where no toggle
    /// shows.
    enum Version { case draft, enhanced, raw }

    @Published private(set) var isPresented = false
    /// The editable text. Bound by `ComposeReviewView`'s `MultiSelectTextView`.
    @Published var draft: String = "" {
        didSet {
            guard !isSettingDraft, draft != oldValue else { return }
            // User typing: their text now owns the editor. Underline offsets
            // no longer map onto it, and an enhanced delivery must not
            // clobber it.
            userEdited = true
            changedSpans = []
        }
    }
    /// Destination app label shown in the header (e.g. "Slack").
    @Published private(set) var targetAppName: String = ""
    /// The as-heard transcript — immutable reference for the RAW face and the
    /// edit signal.
    @Published private(set) var rawText: String = ""
    /// The delivered enhanced text; nil until enhancement completes (or when
    /// enhancement never ran). Non-nil ⇒ the ENHANCED|RAW toggle is shown.
    @Published private(set) var enhancedText: String?
    /// True while the panel is up ahead of a still-running enhancement.
    @Published private(set) var isEnhancing = false
    @Published var activeVersion: Version = .enhanced
    /// Word-diff changed-run count of enhanced vs raw, for the change tag.
    @Published private(set) var changeCount = 0
    /// UTF-16 ranges of changed words in `draft` (valid only while `draft` is
    /// the untouched enhanced text) — accent underlines in the editor.
    @Published private(set) var changedSpans: [NSRange] = []
    /// What `draft` descends from — the editable draft always lives on the
    /// face matching its lineage; the other face is a read-only reference.
    /// .raw until an enhanced delivery replaces the draft (a delivery deferred
    /// by edits/selection does NOT) or the user opts in via the toggle.
    @Published private(set) var draftBase: Version = .enhanced

    /// Sticky once true — an edit-then-undo keeps downstream decisions stable.
    @Published private(set) var userEdited = false
    /// Sticky once an enhanced delivery was deferred (by edits OR a live
    /// selection) — drives the DRAFT segment's existence for the session.
    @Published private(set) var deliveryDeferred = false
    /// Non-empty selection in the editor — user intent like an edit: an
    /// enhanced delivery must not swap the text out from under it (a restored
    /// range would land on different characters after insertions).
    private var hasNonEmptySelection = false
    private var isSettingDraft = false
    /// Bumped on every `present` — a late `deliverEnhanced` from a previous
    /// dictation (or one whose panel was already committed/cancelled) is dropped.
    private var sessionToken = 0

    private var panel: ReviewTrayPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var onCommit: ((_ finalText: String, _ enhancedText: String?, _ fromRawLineage: Bool) -> Void)?
    private var lastContentHeight: CGFloat = defaultHeight

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "ComposeReview")

    // MARK: - Present / commit / cancel

    /// Show the editable preview. May be called while enhancement is still
    /// running (`isEnhancing: true`) — the raw transcript is editable at once
    /// and `deliverEnhanced` swaps the result in when it lands. `onCommit`
    /// runs AFTER the panel has ordered out and focus has settled back onto
    /// the target field (so the paste lands in the right place), receiving
    /// the user's final text plus the enhanced reference the panel had
    /// actually received by then (nil = pasted ahead of / without enhancement)
    /// and whether the final text descends from the raw face (the RAW segment
    /// was active — deferred-by-edit drafts live there) — an enhanced→final
    /// edit signal would be wrong there.
    /// Returns the session token `deliverEnhanced` must echo.
    @discardableResult
    func present(
        rawText: String,
        enhancedText: String?,
        isEnhancing: Bool,
        onCommit: @escaping (_ finalText: String, _ enhancedText: String?, _ fromRawLineage: Bool) -> Void
    ) -> Int {
        // Rebuild the panel every present. A reused panel silently loses its
        // cross-Space / full-screen-auxiliary membership over the app's lifetime,
        // after which re-asserting the same `collectionBehavior` does NOT restore
        // it — and `makeKeyAndOrderFront` would then teleport the user OFF their
        // full-screen Space to wherever the panel was stranded (Desktop 2),
        // breaking the paste. A fresh panel re-registers correctly (relaunch-equivalent).
        rebuildPanel()
        sessionToken += 1
        self.onCommit = onCommit
        // The frontmost app right now is where the paste will land on ⌘↵.
        self.targetAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        self.rawText = rawText
        self.enhancedText = enhancedText
        self.isEnhancing = isEnhancing
        self.activeVersion = enhancedText != nil ? .enhanced : .draft
        setDraft(enhancedText ?? rawText)
        draftBase = enhancedText != nil ? .enhanced : .raw
        userEdited = false
        deliveryDeferred = false
        hasNonEmptySelection = false
        let diff = Self.diff(enhanced: enhancedText, raw: rawText)
        changeCount = diff.count
        changedSpans = diff.spans
        isPresented = true
        positionPanel()
        // Key (so the editor types) but non-activating (the user's app stays
        // frontmost) — focus returns to it on orderOut.
        panel?.makeKeyAndOrderFront(nil)
        logger.notice("present – app=\(self.targetAppName, privacy: .public) chars=\(self.draft.count, privacy: .public) enhancing=\(isEnhancing, privacy: .public)")
        return sessionToken
    }

    /// Enhancement finished for the dictation that presented `session`.
    /// nil = enhancement failed; just clear the ENHANCING state (raw stays
    /// editable). Dropped (returns false) when the panel was already
    /// committed/cancelled or a newer dictation re-presented it — the pending
    /// result must never race dismissal, and the caller uses the same false
    /// to suppress failure UI for a panel the user already left. Returns true
    /// when the live panel consumed the delivery. If the user edited (or holds
    /// a non-empty selection) meanwhile, their text is kept and the
    /// toggle/change tag quietly appear instead.
    @discardableResult
    func deliverEnhanced(_ text: String?, session: Int) -> Bool {
        guard isPresented, session == sessionToken, isEnhancing else {
            logger.notice("deliverEnhanced dropped – stale session or dismissed panel")
            return false
        }
        isEnhancing = false
        guard let text else { return true }
        enhancedText = text
        let diff = Self.diff(enhanced: text, raw: rawText)
        changeCount = diff.count
        if userEdited || hasNonEmptySelection {
            changedSpans = []
            // Deferred (edits OR a live selection): the raw-lineage draft gets
            // its own DRAFT segment, selected — the editor stays mounted with
            // the same view identity, so the selection/multi-select survives.
            // ENHANCED becomes the read-only AI preview (one-shot adoption via
            // selectVersion while the draft is verbatim raw); RAW stays the
            // pristine reference.
            deliveryDeferred = true
            activeVersion = .draft
        } else {
            changedSpans = diff.spans
            setDraft(text)
            draftBase = .enhanced
            activeVersion = .enhanced
        }
        logger.notice("deliverEnhanced applied – keptUserText=\(self.userEdited || self.hasNonEmptySelection, privacy: .public) changes=\(self.changeCount, privacy: .public)")
        return true
    }

    /// Selection tracking from `MultiSelectTextView` (see
    /// `hasNonEmptySelection`).
    func noteSelection(nonEmpty: Bool) {
        hasNonEmptySelection = nonEmpty
    }

    /// Toggle click. Selecting ENHANCED while the draft is a verbatim,
    /// unedited copy of the raw transcript adopts the enhancement one-shot
    /// (the draft becomes the editable enhanced text). An EDITED raw-lineage
    /// draft is never clobbered — ENHANCED then shows a read-only preview
    /// (`ComposeReviewView` derives that from `draftBase`).
    func selectVersion(_ version: Version) {
        if version == .enhanced, draftBase == .raw, draft == rawText, let enhancedText {
            setDraft(enhancedText)
            draftBase = .enhanced
            changedSpans = Self.diff(enhanced: enhancedText, raw: rawText).spans
        }
        activeVersion = version
    }

    /// ⌘↵ — capture EXACTLY what the active face shows (editable draft on the
    /// face matching its lineage, the read-only reference on the other), hide
    /// the panel so focus returns to the target app, then (after a short
    /// settle) run the paste callback.
    func commit() {
        guard isPresented else { return }
        let text: String
        let faceName: String
        switch activeVersion {
        case .draft:
            text = draft
            faceName = "draft"
        case .raw:
            text = rawText
            faceName = "raw"
        case .enhanced:
            text = draftBase == .enhanced ? draft : (enhancedText ?? draft)
            faceName = "enhanced"
        }
        let enhancedRef = enhancedText
        let fromRawLineage = activeVersion != .enhanced
        let callback = onCommit
        isPresented = false
        onCommit = nil
        panel?.orderOut(nil)
        logger.notice("commit – chars=\(text.count, privacy: .public) version=\(faceName, privacy: .public) rawLineage=\(fromRawLineage, privacy: .public)")
        // Settle: let focus return to the now-frontmost target field before the
        // auto-vocab focus capture + Cmd+V fire (otherwise they'd target us).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) {
            callback?(text, enhancedRef, fromRawLineage)
        }
    }

    /// Esc — dismiss without pasting.
    func cancel() {
        guard isPresented else { return }
        isPresented = false
        onCommit = nil
        panel?.orderOut(nil)
        logger.notice("cancel")
    }

    private func setDraft(_ text: String) {
        isSettingDraft = true
        draft = text
        isSettingDraft = false
    }

    /// Changed-run count + changed-word ranges (UTF-16, in `enhanced`) via the
    /// existing WordDiffEngine token diff. Its tokens are punctuation-stripped
    /// and the LCS is case-insensitive, so punctuation/case-only edits are
    /// invisible here — the tag undercounts them; span placement is best-effort
    /// (sequential substring search).
    private static func diff(enhanced: String?, raw: String) -> (count: Int, spans: [NSRange]) {
        guard let enhanced, enhanced != raw else { return (0, []) }
        let ops = WordDiffEngine.tokenLevelDiff(original: raw, edited: enhanced)
        let ns = enhanced as NSString
        var spans: [NSRange] = []
        var count = 0
        var inRun = false
        var cursor = 0
        func locate(_ token: String) -> NSRange? {
            guard cursor < ns.length else { return nil }
            let found = ns.range(of: token, range: NSRange(location: cursor, length: ns.length - cursor))
            guard found.location != NSNotFound else { return nil }
            cursor = found.location + found.length
            return found
        }
        for op in ops {
            switch op {
            case .equal(let token):
                inRun = false
                _ = locate(token)
            case .insert(let token):
                if !inRun { count += 1; inRun = true }
                if let range = locate(token) { spans.append(range) }
            case .delete:
                if !inRun { count += 1; inRun = true }
            }
        }
        return (count, spans)
    }

    // MARK: - Panel construction + positioning

    private func rebuildPanel() {
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        let frame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.defaultHeight)
        let newPanel = ReviewTrayPanel(contentRect: frame)
        // AccentObserving: independent NSHostingController root — see MiniWindowManager.
        let root = AnyView(AccentObserving { ComposeReviewView(manager: self) })
        let controller = NSHostingController(rootView: root)
        controller.view.frame = NSRect(origin: .zero, size: frame.size)
        controller.view.autoresizingMask = [.width, .height]
        newPanel.contentView = controller.view
        panel = newPanel
        hostingController = controller
    }

    /// Always screen-centred (static — never restored from a dragged position).
    private func positionPanel() {
        guard let panel else { return }
        panel.setFrame(centeredFrame(height: max(lastContentHeight, 1)), display: false)
    }

    private func centeredFrame(height: CGFloat) -> NSRect {
        let visible = (NSScreen.active ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = visible.midX - Self.panelWidth / 2
        let y = visible.midY - height / 2
        return NSRect(x: x, y: y, width: Self.panelWidth, height: height)
    }

    /// SwiftUI reports the card's fitting size; grow/shrink the panel keeping it
    /// screen-centred (it's static, so a content change re-centres rather than
    /// anchoring to a dragged corner).
    func contentSizeChanged(_ size: CGSize) {
        guard size.height > 0 else { return }
        lastContentHeight = size.height
        guard let panel, isPresented else { return }
        guard abs(size.height - panel.frame.height) > 0.5 else { return }
        panel.setFrame(centeredFrame(height: size.height), display: true)
    }
}
