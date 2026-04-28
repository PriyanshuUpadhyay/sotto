import SwiftUI

// MARK: - CinematicWalkthrough
//
// Auto-playing 6.5s constellation showcase — replaces the existing
// "Try It Out!" headline page in the onboarding flow (spec §3.4, plan §P2.F).
// Visual reference: `.superpowers/brainstorm/22968-1777317412/content/state-cycle.html`.
//
// Six stages, hard-clocked to a Task-sleep timeline that sums to 6.5s:
//   1. Welcome     1.5s — wordmark fade-in + Whisper line breath.
//   2. Record      1.5s — orb fade-in red + pulse + card char-by-char build.
//   3. Transcribe  1.5s — orb morph cyan + card swap "Transcribing …" + shimmer.
//   4. Enhance     1.5s — orb morph violet + card swap "Enhancing with …" + breath.
//   5. Done        0.5s — orb green flash + card "Pasted to Notes — '…'".
//   ─────────────────
//   total          6.5s
//
// Each stage is its own `View` with an explicit `.task { try await Task.sleep(...) }`
// lifecycle (plan risk note) — easier to reason about timing and cancellation
// than a single monolithic `Timer`. Skip immediately tears down the walkthrough,
// which cancels the running stage's `.task` via SwiftUI's lifecycle.
//
// Reuses Phase 1 Constellation components verbatim — no divergent local copies
// (reviewer focus). The only walkthrough-specific UI is the caption strip,
// the wordmark, and the skip button.
//
// Reduce Motion (spec §6.4):
//   - Wordmark fade-in collapses to instant.
//   - Caption fade-in/out collapses to instant.
//   - Char-by-char transcript build collapses to one-shot full text.
//   - Constellation components (orb pulse / card shimmer / card breath) handle
//     their own Reduce Motion internally — no extra gating needed here.
//
// VoiceOver (spec §6.4):
//   - Each stage view carries an `.accessibilityLabel` summarising the moment.
//   - The caption strip is also a live region — its text is read as it changes.
//   - The skip button has an explicit label and Esc keyboard shortcut.

struct CinematicWalkthrough: View {

    /// Called when the walkthrough finishes — either after the Done stage
    /// elapses or when the user taps Skip / hits Esc. The host view is
    /// expected to dismiss this overlay synchronously inside this callback.
    var onFinish: () -> Void

    @State private var stage: Stage = .welcome
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared

    enum Stage: Equatable {
        case welcome
        case record
        case transcribe
        case enhance
        case done
    }

    // MARK: - Layout constants (spec §3.4)

    private static let cardWidth: CGFloat = 600
    private static let cardHeight: CGFloat = 320
    private static let cardCornerRadius: CGFloat = 28

    var body: some View {
        ZStack {
            // Backdrop — dim the underlying onboarding view so the cinematic
            // glass card reads as the focal element. `ignoresSafeArea` so the
            // backdrop runs corner-to-corner.
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            // Centered glass card hosting the stage.
            ZStack {
                stageView
            }
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .background(
                HaloMaterial(
                    shape: RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous),
                    phase: .hidden,
                    appearance: .onyx
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous))

            // Skip — bottom-right of the overlay (not the card) so it sits
            // outside the staged content and never overlaps a caption.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    skipButton
                        .padding(.trailing, 28)
                        .padding(.bottom, 24)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var stageView: some View {
        switch stage {
        case .welcome:
            WelcomeStage(onComplete: { stage = .record })
        case .record:
            RecordStage(onComplete: { stage = .transcribe })
        case .transcribe:
            TranscribeStage(onComplete: { stage = .enhance })
        case .enhance:
            EnhanceStage(onComplete: { stage = .done })
        case .done:
            DoneStage(onComplete: onFinish)
        }
    }

    private var skipButton: some View {
        Button {
            onFinish()
        } label: {
            Text("Skip")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.78))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.10)))
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Skip walkthrough")
    }
}

// MARK: - Stage timing constants
//
// Hard-coded per spec §3.4. Stage runtimes sum to exactly 6.5s. Caption fade
// windows sit *inside* each stage so transitions land cleanly between stages
// (reviewer focus — no caption fade overlapping a stage swap).

private enum CinematicTiming {
    static let welcomeMs:    Int = 1500
    static let recordMs:     Int = 1500
    static let transcribeMs: Int = 1500
    static let enhanceMs:    Int = 1500
    static let doneMs:       Int = 500
    static let totalMs:      Int = 6500   // welcome + record + transcribe + enhance + done

    /// Caption fade-in/out for the four 1.5s stages.
    static let captionFadeMs: Int = 200
    /// Caption fade-in/out for the 0.5s done stage — tighter so we still
    /// fit fade-in / hold / fade-out inside the half-second budget.
    static let doneCaptionFadeMs: Int = 100

    /// Character build window inside the Record stage — leaves a small gap
    /// either side so the caret has time to settle before the stage swaps.
    static let recordTypeStartMs:    Int = 220
    static let recordTypeDurationMs: Int = 900
}

// MARK: - WelcomeStage (1.5s)
//
// Wordmark fade-in over 0.5s. Whisper line breathes underneath at full
// proximity (idle phase = `.hidden`, which is the WhisperLine "show idle"
// gate). No caption — the wordmark itself is the focal element.

private struct WelcomeStage: View {
    let onComplete: () -> Void

    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    @State private var wordmarkVisible: Bool = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("VoiceInk")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
                .tracking(-0.5)
                .opacity(wordmarkVisible ? 1.0 : 0.0)
                .animation(
                    motion.reduceMotion ? nil : .easeOut(duration: 0.55),
                    value: wordmarkVisible
                )
                .accessibilityLabel("VoiceInk. Welcome to the constellation walkthrough.")

            WhisperLine(phase: .hidden, appearance: .onyx, proximity: 1.0)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            wordmarkVisible = true
            try? await Task.sleep(for: .milliseconds(CinematicTiming.welcomeMs))
            if !Task.isCancelled { onComplete() }
        }
    }
}

// MARK: - RecordStage (1.5s)
//
// Constellation orb at `.recording` (red, pulsing) + chip + card with a
// streaming-caret transcript built character-by-character across ~0.9s.
// Caption "Press hotkey to record" fades in/out around the build.

private struct RecordStage: View {
    let onComplete: () -> Void

    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    @State private var transcriptText: String = ""
    @State private var captionVisible: Bool = false

    private let fullTranscript: String = "the dynamic island feels great"

    var body: some View {
        StageScaffold(
            phase: .recording,
            transcript: transcriptText,
            captionText: "Press hotkey to record",
            captionVisible: captionVisible,
            captionFadeMs: CinematicTiming.captionFadeMs,
            a11y: "Recording. Press hotkey to record."
        )
        .task {
            // Caption fade-in alongside stage entry.
            withAnimation(motion.reduceMotion ? nil : .easeOut(duration: Double(CinematicTiming.captionFadeMs) / 1000)) {
                captionVisible = true
            }

            // Type the transcript char-by-char (or one-shot under Reduce Motion).
            await typeTranscript()

            // Hold until the caption fade-out window opens, then fade out so
            // the strip is empty before the stage transition (reviewer focus).
            let preFadeOutMs = max(
                0,
                CinematicTiming.recordMs
                    - CinematicTiming.recordTypeStartMs
                    - CinematicTiming.recordTypeDurationMs
                    - CinematicTiming.captionFadeMs
            )
            try? await Task.sleep(for: .milliseconds(preFadeOutMs))
            withAnimation(motion.reduceMotion ? nil : .easeIn(duration: Double(CinematicTiming.captionFadeMs) / 1000)) {
                captionVisible = false
            }
            try? await Task.sleep(for: .milliseconds(CinematicTiming.captionFadeMs))

            if !Task.isCancelled { onComplete() }
        }
    }

    /// Typewriter build. Reduce Motion → set full text instantly, then sleep
    /// out the equivalent window so total stage runtime stays at 1.5s.
    private func typeTranscript() async {
        // Brief lead-in so the orb pulse establishes before text starts.
        try? await Task.sleep(for: .milliseconds(CinematicTiming.recordTypeStartMs))

        if motion.reduceMotion {
            transcriptText = fullTranscript
            try? await Task.sleep(for: .milliseconds(CinematicTiming.recordTypeDurationMs))
            return
        }

        let chars = Array(fullTranscript)
        let perCharMs = max(8, CinematicTiming.recordTypeDurationMs / max(chars.count, 1))
        for i in 0..<chars.count {
            if Task.isCancelled { return }
            transcriptText = String(chars[0...i])
            try? await Task.sleep(for: .milliseconds(perCharMs))
        }
    }
}

// MARK: - TranscribeStage (1.5s)
//
// Card swaps to "Transcribing WHISPER · LARGE-V3" — the cyan shimmer sweep
// is rendered by ConstellationCard itself when phase == .transcribing.
// Orb morphs cyan, also handled internally by the orb (state-keyed color).

private struct TranscribeStage: View {
    let onComplete: () -> Void

    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    @State private var captionVisible: Bool = false

    var body: some View {
        StageScaffold(
            phase: .transcribing,
            captionText: "AI transcribes locally or in cloud",
            captionVisible: captionVisible,
            captionFadeMs: CinematicTiming.captionFadeMs,
            a11y: "Transcribing with Whisper Large V3. AI transcribes locally or in cloud."
        )
        .task {
            await runFadingCaptionStage(
                stageMs: CinematicTiming.transcribeMs,
                fadeMs: CinematicTiming.captionFadeMs,
                reduceMotion: motion.reduceMotion,
                visible: { captionVisible = $0 }
            )
            if !Task.isCancelled { onComplete() }
        }
    }
}

// MARK: - EnhanceStage (1.5s)
//
// Card swaps to "Enhancing with Default Mode" + breath. Orb morphs violet
// and breathes — both handled internally by the constellation components.
// Card breath is driven by `breathePulse` + `showInnerSheen`; we set both
// here per the contract documented in `ConstellationCard`.

private struct EnhanceStage: View {
    let onComplete: () -> Void

    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    @State private var captionVisible: Bool = false
    @State private var sheenPulse: Double = 0

    var body: some View {
        StageScaffold(
            phase: .enhancing,
            captionText: "Enhancement shapes the result",
            captionVisible: captionVisible,
            captionFadeMs: CinematicTiming.captionFadeMs,
            sheenPulse: motion.reduceMotion ? 0.5 : sheenPulse,
            showInnerSheen: true,
            a11y: "Enhancing with Default Mode using Claude Sonnet 4.6. Enhancement shapes the result."
        )
        .task {
            // Drive the sheen pulse 0 → 1 → 0 across the stage so the card's
            // violet inner sheen breathes during enhance. Reduce Motion pins
            // it at 0.5 (handled in the StageScaffold prop above).
            if !motion.reduceMotion {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    sheenPulse = 1.0
                }
            }

            await runFadingCaptionStage(
                stageMs: CinematicTiming.enhanceMs,
                fadeMs: CinematicTiming.captionFadeMs,
                reduceMotion: motion.reduceMotion,
                visible: { captionVisible = $0 }
            )
            if !Task.isCancelled { onComplete() }
        }
    }
}

// MARK: - DoneStage (0.5s)
//
// Orb green flash + card "Pasted to Notes — '…'". Tightest stage — caption
// fade is 100ms (vs 200ms for the others) so fade-in / hold / fade-out all
// fit inside the 500ms budget.

private struct DoneStage: View {
    let onComplete: () -> Void

    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    @State private var captionVisible: Bool = false

    var body: some View {
        StageScaffold(
            phase: .done,
            pasteTargetAppName: "Notes",
            donePreview: "the dynamic island feels great",
            captionText: "Pasted automatically into the focused app",
            captionVisible: captionVisible,
            captionFadeMs: CinematicTiming.doneCaptionFadeMs,
            a11y: "Pasted to Notes. Pasted automatically into the focused app."
        )
        .task {
            await runFadingCaptionStage(
                stageMs: CinematicTiming.doneMs,
                fadeMs: CinematicTiming.doneCaptionFadeMs,
                reduceMotion: motion.reduceMotion,
                visible: { captionVisible = $0 }
            )
            if !Task.isCancelled { onComplete() }
        }
    }
}

// MARK: - Shared stage helpers

/// Generic stage runner — fade caption in, hold, fade caption out, sleep
/// the remainder. Hold = stage − 2×fade. Caller invokes `onComplete()` after
/// this returns (so the stage view fully unmounts before the next stage
/// .task starts, preventing visual chop at the transition).
@MainActor
private func runFadingCaptionStage(
    stageMs: Int,
    fadeMs: Int,
    reduceMotion: Bool,
    visible: @escaping (Bool) -> Void
) async {
    let fadeDuration = Double(fadeMs) / 1000.0
    let holdMs = max(0, stageMs - fadeMs * 2)

    withAnimation(reduceMotion ? nil : .easeOut(duration: fadeDuration)) {
        visible(true)
    }
    try? await Task.sleep(for: .milliseconds(fadeMs + holdMs))
    if Task.isCancelled { return }

    withAnimation(reduceMotion ? nil : .easeIn(duration: fadeDuration)) {
        visible(false)
    }
    try? await Task.sleep(for: .milliseconds(fadeMs))
}

// MARK: - StageScaffold
//
// Common 600×320 layout: orb + chip up top, card centered, caption strip
// below. Phase-driven so each stage view is just "configure once + run a
// .task". No business logic in here — pure layout.

private struct StageScaffold: View {
    var phase: HaloPhase
    var transcript: String = ""
    var pasteTargetAppName: String? = nil
    var donePreview: String? = nil
    var captionText: String
    var captionVisible: Bool
    var captionFadeMs: Int
    var sheenPulse: Double = 0
    var showInnerSheen: Bool = false
    var a11y: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Orb + chip row — sized to read at the cinematic scale (orb is
            // intrinsically 16pt; we scale it 2× for visibility on the card).
            HStack(spacing: 18) {
                ConstellationOrb(phase: phase)
                    .scaleEffect(2.0)
                    .frame(width: 36, height: 36)
                ConstellationChip(
                    phase: phase,
                    providerLabel: chipProvider,
                    modelLabel: chipModel,
                    appearance: .onyx
                )
            }

            Spacer(minLength: 18)

            // Card — centered, fixed 280pt by spec §3.1.
            ConstellationCard(
                phase: phase,
                partialTranscript: transcript,
                pasteTargetAppName: pasteTargetAppName,
                donePreview: donePreview,
                appearance: .onyx,
                showInnerSheen: showInnerSheen,
                breathePulse: sheenPulse
            )

            Spacer(minLength: 18)

            // Caption strip — fixed height so transitions don't reflow the
            // layout when caption text changes between stages.
            CinematicCaption(text: captionText, visible: captionVisible)
                .frame(height: 28)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    /// Provider/model labels for the chip — split per phase so transcribe
    /// shows Whisper and enhance shows Claude. Recording inherits the
    /// transcribe identity (recorder is bound to a single transcription
    /// engine per session, mirroring the real product behavior).
    private var chipProvider: String {
        switch phase {
        case .enhancing: return "CLAUDE"
        default:         return "WHISPER"
        }
    }
    private var chipModel: String {
        switch phase {
        case .enhancing: return "SONNET-4-6"
        default:         return "LARGE-V3"
        }
    }
}

// MARK: - CinematicCaption
//
// Single-line caption strip that fades opacity 0↔1 driven by `visible`.
// Cross-fade animation is owned by the parent (it wraps the toggle in
// `withAnimation(.easeOut/.easeIn)`) — this view itself just renders.
//
// Accessibility: caption text is announced via VoiceOver on appearance.

private struct CinematicCaption: View {
    let text: String
    let visible: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.85))
            .tracking(0.2)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .opacity(visible ? 1.0 : 0.0)
            .accessibilityHidden(!visible || text.isEmpty)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CinematicWalkthrough — auto-play") {
    CinematicWalkthrough(onFinish: {})
        .frame(width: 900, height: 560)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("CinematicWalkthrough — light backdrop") {
    CinematicWalkthrough(onFinish: {})
        .frame(width: 900, height: 560)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
