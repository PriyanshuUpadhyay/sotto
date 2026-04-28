import SwiftUI

// MARK: - HaloRecorderView
//
// Thin adapter — used to be a 580 LOC pill renderer; in P1.G it became a
// pass-through to `ConstellationContainer` so both window managers
// (`NotchWindowManager`, `MiniWindowManager`) keep their existing
// constructor and we don't have to touch every call site at once.
//
// The constellation pieces (orb, chip, card, whisper line) own all
// per-state visuals + motion. The breathe pulse, popover plumbing,
// minPillWidth / maxPillWidth math, the `pill`/`mainRow`/`liveTextPanel`
// stack, the `RecordingDot` / `TranscribingShimmerDot` glyphs, and the
// `EnhancingIdentity` view that lived in v1 are all gone. The parts the
// constellation re-uses — `StreamingCaretTranscript` — moved with this
// file (kept below so existing references continue to resolve).

struct HaloRecorderView<S: RecorderStateProvider & ObservableObject, WM: ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    @ObservedObject var windowManager: WM
    var isVisible: () -> Bool
    var mode: HaloShape.Mode

    var body: some View {
        if isVisible() {
            ConstellationContainer(
                stateProvider: stateProvider,
                recorder: recorder,
                aiService: aiService,
                mode: mode
            )
        }
    }
}

// MARK: - Streaming caret transcript (live partial)
//
// Re-used by `ConstellationCard` for `.recording`/`.liveText`. Lives here
// because v1 already exported it from this file; moving would require
// touching the constellation card's import paths. Spec §3.1 recording
// content row.

struct StreamingCaretTranscript: View {
    let text: String
    /// Maximum text-area width — text wraps at this width so the pill stays at a
    /// stable size during liveText (no jittery re-layout per partial-transcript
    /// chunk). Caller passes the inner content width of the pill.
    var maxWidth: CGFloat = 480

    private var displayText: String {
        // Keep last ~140 chars so the panel doesn't grow visually.
        if text.count > 140 {
            let idx = text.index(text.endIndex, offsetBy: -140)
            return "…" + text[idx...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    var body: some View {
        // Vertical scroll: text wraps within the pill width; if it grows beyond
        // the panel's clamped height, the user can scroll. Auto-scrolls to the
        // bottom when new partial-transcript chunks arrive so the caret stays
        // in view. No head-truncation — the user sees the full transcript.
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(displayText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .frame(maxWidth: maxWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    BlinkingCaret()
                }
                .frame(maxWidth: maxWidth + 8, alignment: .leading)
                .id("liveTextEnd")
            }
            .frame(maxWidth: maxWidth + 8, alignment: .leading)
            .onChange(of: displayText) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("liveTextEnd", anchor: .bottom)
                }
            }
            .transaction { $0.disablesAnimations = true }
        }
    }
}

private struct BlinkingCaret: View {
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 0.75)
            .fill(Color.white.opacity(on ? 0.7 : 0.0))
            .frame(width: 1.5, height: 14)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    on = false
                }
            }
    }
}
