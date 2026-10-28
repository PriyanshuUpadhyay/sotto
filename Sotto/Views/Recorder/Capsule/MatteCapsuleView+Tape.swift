import SwiftUI
import AppKit

extension MatteCapsuleView {
    static func contentWidth(of words: [StreamedWord], italicLast: Bool) -> CGFloat {
        guard !words.isEmpty else { return 0 }
        var total = CGFloat(words.count - 1) * wordSpacing
        for (index, word) in words.enumerated() {
            let font = (italicLast && index == words.count - 1)
                ? measureFontItalic : measureFont
            total += (word.text as NSString).size(withAttributes: [.font: font]).width
            total += CGFloat(word.text.count) * tapeTracking
        }
        return total
    }

    /// Conveyor (design-mockups/01): leading-aligned with a content shift so
    /// an underfilled tape hugs its left edge (the reveal mask tracks it) and
    /// an overflowing tape rides older words left; new words fade in + rise
    /// individually; the leading gradient mask dissolves the oldest visible
    /// words. The line is never repainted wholesale — `WordStream` keeps
    /// surviving word identities stable.
    var wordTape: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.wordSpacing) {
            ForEach(tape.words) { word in
                wordText(word)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .glassInkShadow()
        .offset(x: min(0, Self.tapeWidth - tapeContentWidth))
        .frame(width: tapeReveal, height: 28, alignment: .leading)
        .clipped()
        .mask(tapeMask)
    }

    /// Mic bars + tape ride the capsule's own glass. `Glass.regular` blurs AND
    /// dims what is behind it to keep foreground text legible, so a frosted
    /// well here would only be a second sheet of glass inside the first.
    var liveRow: some View {
        HStack(spacing: tapeReveal > 0 ? Self.itemSpacing : 0) {
            if state == .recording, let recorder {
                MicLevelBars(recorder: recorder, reduceMotion: reduceMotion)
            }
            wordTape
        }
    }

    func wordText(_ word: StreamedWord) -> some View {
        // The newest word sits tentative (italic, secondary ink) until the
        // next arrives, then settles. The settle animates ONLY on appends —
        // a rewrite can flip a SURVIVING word tentative (e.g. a trim exposes
        // it as the new last word) and corrections must stay instant.
        let tentative = state == .recording && word.id == tape.words.last?.id
        return Text(word.text)
            .font(.transcript(Self.tapeFontSize))
            .tracking(Self.tapeTracking)
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
    var wordTransition: AnyTransition {
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

    var tapeMask: some View {
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
    func ingest(_ newPartial: String) {
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
}
