import SwiftUI
import AppKit

// MARK: - WordStream
//
// Suffix-diff over the cumulative ASR partial (2026-07 revamp,
// design-mockups/01): the tape animates only APPENDED words; any rewrite of
// earlier content (ASR corrections, trims) rebuilds the visible tail
// instantly — never animate a correction. Pure value type so the diff is
// unit-testable (`WordStreamTests`).

struct StreamedWord: Identifiable, Equatable {
    /// Monotonic per-stream id — an appended word is a NEW identity (its
    /// entrance transition fires) while surviving prefix words keep theirs.
    let id: Int
    let text: String
}

struct WordStream: Equatable {
    enum Change { case none, appended, rewritten }

    /// The FULL token sequence of the current partial — diffing always runs
    /// against the whole prior partial so trims/rewrites that reach behind
    /// the visible window still resolve correctly; the window only decides
    /// which suffix is rendered.
    private var all: [StreamedWord] = []
    private var nextID = 0

    static let windowMax = 16

    /// Visible tail, capped at `windowMax` — older words sit under the leading
    /// fade mask anyway; the cap bounds layout work for long dictations.
    var words: [StreamedWord] { Array(all.suffix(Self.windowMax)) }

    init(partial: String = "") { ingest(partial) }

    @discardableResult
    mutating func ingest(_ partial: String) -> Change {
        let new = partial.split(whereSeparator: \.isWhitespace).map(String.init)
        let old = all.map(\.text)
        guard new != old else { return .none }
        let stable = zip(old, new).prefix(while: ==).count
        all.removeLast(old.count - stable)
        for text in new[stable...] {
            all.append(StreamedWord(id: nextID, text: text))
            nextID += 1
        }
        return (stable == old.count && new.count > old.count) ? .appended : .rewritten
    }
}

// MARK: - MatteCapsuleView
//
// The compact matte recorder HUD (spec §1 + §4) — replaces the Constellation
// pill as the hosted recorder root. A flat near-black capsule where the state
// color enters ONLY via the glyph / dot / edge, never a full fill (keeps it
// calm against the matte surface).
//
// Pure & presentational: state, elapsed, and partial text are passed in. The
// live host (`MatteCapsuleContainer`) derives them from the engine and drives
// `reduceMotion` from `@Environment(\.accessibilityReduceMotion)`; the snapshot
// harness passes `reduceMotion: true` for a still frame.
//
// A11y contract (P1a): non-color cue = `StateCue.glyph`; spoken label =
// `StateCue.voiceOverLabel`; all motion routes through `Motion.*(reduceMotion:)`
// / `MotionTokens` (word tape).

struct MatteCapsuleView: View {
    let state: CapsuleState
    /// Seconds since recording armed — rendered as a tabular mono mm:ss timer
    /// while `.recording`.
    let elapsed: TimeInterval
    /// Cumulative live partial transcript — word-streamed onto the serif tape
    /// while recording/processing (design-mockups/01 conveyor).
    let partial: String
    /// Cold-start signal: when `.processing` and the model is still loading,
    /// the leading label reads "warming up" instead of "transcribing" so a long
    /// first-dictation load doesn't read as a freeze.
    let warming: Bool
    /// True while the engine is in `.enhancing` — the visual `.processing`
    /// state collapses transcribe+enhance into one hue (council 4-state cut),
    /// but the label and VoiceOver still name the actual step.
    let enhancing: Bool
    let reduceMotion: Bool
    /// Cause of the surfaced failure — rendered in place of "failed" and
    /// deciding which recovery the chip offers. Nil outside `.fail`.
    let failure: RecorderUIManager.FailureCode?
    /// `.fail` retry action — wired to the engine retry path by the host.
    let onRetry: () -> Void
    /// `.fail` fallback when retrying cannot help (no model installed).
    let onOpenSettings: () -> Void

    /// Oscillation target for the recording-dot pulse. Driven explicitly by
    /// `syncPulse` (withAnimation repeatForever on entering `.recording`, a
    /// no-animation snap back on leaving) because the capsule now keeps ONE
    /// structural identity across the whole live stretch — an
    /// onAppear-triggered implicit `.animation` would fire only on the first
    /// recording and could leak its repeatForever into later states.
    @State private var glyphDimmed = false
    /// Seeded from `partial` at init so the FIRST render (incl. the snapshot
    /// harness, which never runs onAppear/onChange) already shows the words;
    /// `onChange(of: partial)` drives the per-word choreography after.
    @State private var tape: WordStream
    @State private var lastChange: WordStream.Change = .none
    /// Measured width of the visible tape words (font metrics, no layout
    /// reads) — drives the conveyor shift and the reveal mask.
    @State private var tapeContentWidth: CGFloat
    /// Revealed tape span, ratcheted (grows with content, never shrinks
    /// mid-dictation) and clamped to `tapeWidth`; resets when the tape empties.
    @State private var tapeReveal: CGFloat

    init(state: CapsuleState,
         elapsed: TimeInterval = 0,
         partial: String = "",
         warming: Bool = false,
         enhancing: Bool = false,
         reduceMotion: Bool = false,
         failure: RecorderUIManager.FailureCode? = nil,
         onRetry: @escaping () -> Void = {},
         onOpenSettings: @escaping () -> Void = {}) {
        self.state = state
        self.elapsed = elapsed
        self.partial = partial
        self.warming = warming
        self.enhancing = enhancing
        self.reduceMotion = reduceMotion
        self.failure = failure
        self.onRetry = onRetry
        self.onOpenSettings = onOpenSettings
        let seeded = WordStream(partial: partial)
        _tape = State(initialValue: seeded)
        let width = Self.contentWidth(of: seeded.words, italicLast: state == .recording)
        _tapeContentWidth = State(initialValue: width)
        _tapeReveal = State(initialValue: min(Self.tapeWidth, width))
    }

    var body: some View {
        HStack(spacing: Self.itemSpacing) {
            stateGlyph

            if let label = primaryLabel {
                Text(label)
                    .font(.mono(12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.inkPrimary)
                    .lineLimit(1)
            }

            if state == .recording { escHint }

            if state == .recording || state == .processing {
                wordTape
            }

            if state == .fail {
                if failure?.isRetryable == false { settingsChip } else { retryChip }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(capsuleBody)
        .overlay(capsuleEdge)
        .clipShape(Capsule(style: .continuous))
        // Mockup's .cap-live technique: the FRAME stays at reserved width (the
        // tape window is always 220pt in layout) while the VISIBLE surface is
        // masked to the content width from the trailing edge — mask + offset
        // animate, the frame never does. `revealOffset` recenters the visible
        // pill in the oversized frame (translateX(clip/2) in the mockup).
        .mask(revealMask)
        // Floating object → soft drop shadow (spec §1: shadows only on floating).
        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 12)
        .offset(x: revealOffset)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(StateCue.voiceOverLabel(for: state, enhancing: enhancing,
                                                    failureRetryable: failure?.isRetryable ?? true))
        .onAppear { syncPulse(for: state) }
        .onChange(of: state) { _, newState in syncPulse(for: newState) }
        .onChange(of: reduceMotion) { _, _ in syncPulse(for: state) }
        .onChange(of: partial) { _, newPartial in ingest(newPartial) }
    }

    // MARK: - Word tape

    /// The tape window is RESERVED at a fixed width in LAYOUT for the whole
    /// live stretch so the frame never animates (SwiftUI port rule); the
    /// visible capsule surface is masked to `tapeReveal` and grows with
    /// content (mockup .cap-live clip-path technique).
    private static let tapeWidth: CGFloat = 220
    /// Leading fade-out span of the edge mask (the "recency window" edge).
    private static let tapeFade: CGFloat = 28
    /// Inter-word gap — must match the tape HStack spacing (width math).
    private static let wordSpacing: CGFloat = 5
    /// Leading-cluster HStack spacing before the tape (collapsed by the
    /// reveal mask while the tape is empty).
    private static let itemSpacing: CGFloat = 10

    private var liveTape: Bool { state == .recording || state == .processing }

    /// Trailing span of the reserved frame hidden by the reveal mask. Empty
    /// tape also swallows the HStack gap before it, so the pill hugs
    /// dot + timer at record start.
    private var revealInset: CGFloat {
        guard liveTape else { return 0 }
        guard tapeReveal > 0 else { return Self.tapeWidth + Self.itemSpacing }
        return Self.tapeWidth - tapeReveal
    }

    /// Recenter the visible pill within the oversized frame.
    private var revealOffset: CGFloat { revealInset / 2 }

    private var revealMask: some View {
        Capsule(style: .continuous).padding(.trailing, revealInset)
    }

    /// New York 13pt (`Font.transcript(13)`) metrics twin for cheap
    /// measurement — no layout reads of the rendered tape.
    private static let measureFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 13)
        guard let descriptor = base.fontDescriptor.withDesign(.serif),
              let serif = NSFont(descriptor: descriptor, size: 13) else { return base }
        return serif
    }()

    /// Italic twin — the tentative (newest) word renders `.italic`, which is
    /// measurably wider than roman at this size; measuring it roman clips.
    private static let measureFontItalic: NSFont = {
        let descriptor = measureFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: 13) ?? measureFont
    }()

    static func contentWidth(of words: [StreamedWord], italicLast: Bool) -> CGFloat {
        guard !words.isEmpty else { return 0 }
        var total = CGFloat(words.count - 1) * wordSpacing
        for (index, word) in words.enumerated() {
            let font = (italicLast && index == words.count - 1)
                ? measureFontItalic : measureFont
            total += (word.text as NSString).size(withAttributes: [.font: font]).width
        }
        return total
    }

    /// Conveyor (design-mockups/01): leading-aligned with a content shift so
    /// an underfilled tape hugs its left edge (the reveal mask tracks it) and
    /// an overflowing tape rides older words left; new words fade in + rise
    /// individually; the leading gradient mask dissolves the oldest visible
    /// words. The line is never repainted wholesale — `WordStream` keeps
    /// surviving word identities stable.
    private var wordTape: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.wordSpacing) {
            ForEach(tape.words) { word in
                wordText(word)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: min(0, Self.tapeWidth - tapeContentWidth))
        .frame(width: Self.tapeWidth, height: 28, alignment: .leading)
        .clipped()
        .mask(tapeMask)
    }

    private func wordText(_ word: StreamedWord) -> some View {
        // The newest word sits tentative (italic, secondary ink) until the
        // next arrives, then settles. The settle animates ONLY on appends —
        // a rewrite can flip a SURVIVING word tentative (e.g. a trim exposes
        // it as the new last word) and corrections must stay instant.
        let tentative = state == .recording && word.id == tape.words.last?.id
        return Text(word.text)
            .font(.transcript(13))
            .italic(tentative)
            .foregroundStyle(tentative ? Palette.inkSecondary : Palette.inkPrimary)
            .lineLimit(1)
            .animation(lastChange == .appended && !reduceMotion ? MotionTokens.wordSettle : nil,
                       value: tentative)
            .transition(wordTransition)
    }

    /// Insertion choreography by last diff outcome: appended words fade+rise
    /// (Reduce Motion: opacity-only fade); rewrites are `.identity` — a
    /// correction swaps instantly. Removals are always instant (trimmed words
    /// are already under the mask).
    private var wordTransition: AnyTransition {
        guard lastChange == .appended else { return .identity }
        if reduceMotion {
            return .asymmetric(insertion: .opacity.animation(MotionTokens.reducedFade),
                               removal: .identity)
        }
        return .asymmetric(
            insertion: .offset(y: MotionTokens.wordRise).combined(with: .opacity)
                .animation(MotionTokens.wordIn),
            removal: .identity
        )
    }

    private var tapeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: Self.tapeFade / Self.tapeWidth),
                .init(color: .black, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    /// Appends slide the conveyor + reveal (`tapeSlide` ambient animation);
    /// rewrites and Reduce Motion mutate without animation — the word
    /// transition's own attached animation still fades appended words in.
    /// The ratchet keeps `tapeReveal` from shrinking on a mid-stream trim;
    /// only an emptied tape (stop / new dictation) resets it, and that reset
    /// still animates the mask (never the frame) unless Reduce Motion.
    private func ingest(_ newPartial: String) {
        var next = tape
        let change = next.ingest(newPartial)
        guard change != .none else { return }
        lastChange = change
        let width = Self.contentWidth(of: next.words, italicLast: state == .recording)
        let reveal = next.words.isEmpty
            ? 0
            : min(Self.tapeWidth, max(tapeReveal, width))
        if reduceMotion {
            tape = next
            tapeContentWidth = width
            tapeReveal = reveal
        } else if change == .appended {
            withAnimation(MotionTokens.tapeSlide) {
                tape = next
                tapeContentWidth = width
                tapeReveal = reveal
            }
        } else {
            // Corrections swap instantly; only the masked reveal glides.
            tape = next
            tapeContentWidth = width
            withAnimation(MotionTokens.tapeSlide) { tapeReveal = reveal }
        }
    }

    // MARK: - Pieces

    /// State color enters here (glyph) — never the body fill. Recording adds a
    /// 1.0s dot pulse; the rest are steady.
    private var stateGlyph: some View {
        Image(systemName: StateCue.glyph(for: state))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(state.color)
            .opacity(glyphDimmed ? 0.45 : 1.0)
            .accessibilityHidden(true)
    }

    /// Entering `.recording` starts the repeatForever oscillation; any other
    /// state (or Reduce Motion) writes an unanimated snap back to full — a new
    /// transaction on the same property, which is what actually cancels a
    /// running repeatForever.
    private func syncPulse(for state: CapsuleState) {
        if state == .recording && !reduceMotion {
            guard !glyphDimmed else { return }
            withAnimation(Motion.pulse(Motion.recordPulse, reduceMotion: reduceMotion)) {
                glyphDimmed = true
            }
        } else {
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) { glyphDimmed = false }
        }
    }

    /// The only abort for a live dictation is ESC, and nothing else on the
    /// surface says so (mockup 01 `.esc-hint`).
    private var escHint: some View {
        Text("esc to cancel")
            .font(.mono(10, weight: .medium))
            .foregroundStyle(Palette.inkSecondary)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule(style: .continuous).fill(Palette.mtRaise2))
            .overlay(Capsule(style: .continuous).strokeBorder(Palette.mtLine, lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var retryChip: some View {
        Button(action: onRetry) {
            Text("⌘R")
                .font(.mono(11, weight: .semibold))
                .foregroundStyle(Palette.stateFail)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous).fill(Palette.mtRaise2)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Palette.stateFail.opacity(0.6), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry")
        .accessibilityHint("Press Command R to retry")
    }

    /// Recovery for a failure a retry cannot fix — the only way out of
    /// `ERR · NO_MODEL` is installing a model in Settings.
    private var settingsChip: some View {
        Button(action: onOpenSettings) {
            Text("settings")
                .font(.mono(11, weight: .semibold))
                .foregroundStyle(Palette.stateFail)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous).fill(Palette.mtRaise2)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Palette.stateFail.opacity(0.6), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Settings")
        .accessibilityHint("Install a transcription model")
    }

    private var capsuleBody: some View {
        Capsule(style: .continuous).fill(Palette.mtRaise)
    }

    private var capsuleEdge: some View {
        // State color tints the edge subtly; matte hairline otherwise. Padded
        // to the revealed span so the stroke hugs the VISIBLE right end (a
        // full-width stroke would be chopped flat by the reveal mask).
        Capsule(style: .continuous)
            .strokeBorder(edgeColor, lineWidth: 1)
            .padding(.trailing, revealInset)
    }

    private var edgeColor: Color {
        switch state {
        case .idleReady: return Palette.mtLine2
        default:         return state.color.opacity(0.55)
        }
    }

    // MARK: - Content derivation

    /// The leading mono label: a mm:ss timer while recording, else a terse
    /// state word so the capsule reads even before any partial arrives.
    private var primaryLabel: String? {
        switch state {
        case .recording:  return Self.timer(elapsed)
        case .processing: return Self.processingLabel(warming: warming, enhancing: enhancing)
        case .commit:     return "pasted"
        case .fail:       return failure?.rawValue ?? "failed"
        case .idleReady:  return "ready"
        }
    }

    /// The `.processing` leading label. "warming up" during a cold-start model
    /// load (so the wait doesn't read as a freeze), "enhancing" once the AI
    /// pass starts (the two can't co-occur — warming clears when transcribing
    /// ends), else "transcribing".
    static func processingLabel(warming: Bool, enhancing: Bool) -> String {
        if warming { return "warming up" }
        return enhancing ? "enhancing" : "transcribing"
    }

    static func timer(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

#if DEBUG
#Preview("Matte capsule — all states") {
    VStack(spacing: 16) {
        ForEach(CapsuleState.allCases, id: \.self) { s in
            MatteCapsuleView(state: s, elapsed: 12.4,
                             partial: "ship the parser", reduceMotion: true)
        }
    }
    .padding(40)
    .frame(width: 420)
    .background(Palette.mtCanvas)
    .environment(\.colorScheme, .dark)
}
#endif
