import SwiftUI
import AppKit

// MARK: - ConstellationContainer
//
// Orchestrator for the Phase-1 Constellation recorder. Anchors the three
// satellites (orb / chip / card) plus the WhisperLine over a screen-width
// × 120pt top-strip panel. Panel itself is configured for hit-test
// passthrough (`ignoresMouseEvents = true` on the NSPanel) so menu-bar
// clicks fall through the empty regions — spec §3.1 panel infrastructure.
//
// State:
//   • `RecordingState` → `HaloPhase` mapping (with `.busy` collapsing per
//     v1 behavior — plan §P1.G).
//   • `.done` synthesized from `RecorderStateProvider.lastPasteEvent` —
//     held for 1s after the freshest event, then drops back to the
//     engine-derived phase. Source-of-truth lives on the engine; the
//     orchestrator only mirrors freshness.
//   • Sequencing per spec §2.4 — orb t=0.00, chip t=0.06, card t=0.09 —
//     encoded as `.transition(...).animation(.haloExpand.delay(N))`.
//     NEVER `DispatchQueue.main.asyncAfter` (reviewer focus).
//   • Card `showInnerSheen` + `breathePulse` driven from here so spec §2.3
//     layer-6 violet sheen renders during `.enhancing` (P1.F carry-over).

struct ConstellationContainer<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    @ObservedObject var appearanceDetector: GlassAppearanceDetector = .shared
    @ObservedObject private var powerModeManager: PowerModeManager = .shared
    @StateObject private var proximityMonitor = CursorProximityMonitor()
    @AppStorage("showLiveTextPreview") private var showLiveTextPreview = true

    /// Panel layout mode — `.notch` flanks a physical notch, `.floating`
    /// centers around a virtual one.
    let mode: HaloShape.Mode

    // MARK: - Done-state dwell

    /// Active for ~1s after a fresh `lastPasteEvent`. Synthesizes the engine
    /// `.done` phase that `HaloPhase` doesn't otherwise have a source for.
    @State private var doneActive: Bool = false
    @State private var doneTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        let layout = ConstellationLayout.current(mode: mode)
        let phase = derivedPhase
        // Polish: pause the 60Hz timeline outside `.enhancing`. The breathe
        // pulse is the only thing that needs frame-by-frame updates, and
        // `breathePulse(at:)` already returns 0 for non-enhancing phases —
        // so without this gate the recorder burns CPU re-driving the body
        // while the panel is mounted but idle / recording / transcribing.
        let timelinePaused = phase != .enhancing

        // Drive the breathe pulse with a TimelineView so we don't have to
        // own a repeating animation @State (avoids retain-cycle gotchas
        // noted in plan §P1.B). Pulse is gated to `.enhancing` and reduced
        // to 0.5 under Reduce Motion (still drives sheen at static mid).
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: timelinePaused)) { ctx in
            let pulse = breathePulse(at: ctx.date)
            content(layout: layout, breathePulse: pulse)
        }
        // Republish lastPasteEvent into `doneActive` with a 1s dwell.
        .onChange(of: stateProvider.lastPasteEvent) { _, newEvent in
            handleLastPasteEvent(newEvent)
        }
    }

    // MARK: - Stack

    @ViewBuilder
    private func content(layout: ConstellationLayout, breathePulse: Double) -> some View {
        let phase = derivedPhase
        let appearance = appearanceDetector.current

        ZStack(alignment: .topLeading) {
            // Idle whisper — present below the notch when phase collapses
            // back to `.hidden`. Opacity is internally multiplied by
            // `proximity`; we just hand the value over.
            // TODO(polish): the recorder panel is `orderOut`'d at idle, so
            // the WhisperLine never actually renders ambient. Real fix is a
            // separate always-mounted ambient-strip panel — deferred (needs
            // design discussion). For now the WhisperLine still works
            // correctly during phase transitions while the panel is alive.
            WhisperLine(
                phase: phase,
                appearance: appearance,
                proximity: proximityMonitor.proximity
            )
            .frame(width: 60, height: 2)
            .position(x: layout.cardCenterX, y: layout.whisperY)

            // Constellation satellites — only mounted while phase is
            // visible. The `if` predicate triggers each child's
            // `.transition(...)`; the per-child `.animation()` modifier
            // attached to that transition encodes the §2.4 stagger.
            if phase != .hidden {
                ConstellationOrb(
                    phase: phase,
                    // `audioMeter.averagePower` is a normalized 0…1 (see
                    // `Recorder.audioMeter` plumbing) so we forward it
                    // straight through. Cast to Float to match the orb's
                    // input type.
                    audioMeter: Float(recorder.audioMeter.averagePower),
                    appearance: appearance
                )
                .frame(width: 22, height: 22)
                .position(x: layout.orbX, y: layout.satelliteY)
                .transition(orbTransition)

                ConstellationChip(
                    phase: phase,
                    providerLabel: providerShortName(aiService.selectedProvider),
                    modelLabel: compactModelName(aiService.currentModel),
                    appearance: appearance
                )
                .fixedSize()
                .position(x: layout.chipX, y: layout.satelliteY)
                .transition(chipTransition)

                ConstellationCard(
                    phase: phase,
                    partialTranscript: stateProvider.partialTranscript,
                    pasteTargetAppName: stateProvider.lastPasteEvent?.appName,
                    donePreview: stateProvider.lastPasteEvent?.preview,
                    failureReason: stateProvider.failureReason,
                    activePromptIcon: activePromptIcon,
                    activePromptName: activePromptName,
                    transcriptionEngineLabel: transcriptionEngineLabel,
                    enhancementProviderLabel: enhancementProviderLabel,
                    appearance: appearance,
                    showInnerSheen: phase == .enhancing,
                    breathePulse: breathePulse
                )
                .fixedSize()
                .position(x: layout.cardCenterX, y: layout.cardCenterY)
                .transition(cardTransition)

                // Power Mode active pill (P2.H / spec §3.12) — rendered just
                // below the card during active states when a mode is matched.
                // Fades in over 220ms, cross-fades by id when the matched mode
                // flips. Hidden during .hidden / .done / .failed phases so the
                // constellation card doesn't get cluttered post-action.
                if let activeMode = activePowerModeForPhase(phase) {
                    PowerModeActivePill(
                        emoji: activeMode.emoji,
                        name: activeMode.name,
                        appearance: appearance
                    )
                    .id(activeMode.id)
                    .position(
                        x: layout.cardCenterX,
                        y: layout.cardCenterY + (ConstellationLayout.cardNominalHeight / 2) + 16
                    )
                    // Embed the animation IN the transition so first-mount
                    // fade-in fires (reviewer focus #3 — `.animation(_,value:)`
                    // only fires on id changes, not on insertion). Same
                    // pattern as `cardTransition` / `chipTransition` above.
                    .transition(.opacity.animation(.haloPhaseCrossfade))
                    // Cross-fade on mode flip via id+ambient animation.
                    .animation(.haloPhaseCrossfade, value: activeMode.id)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Returns the active Power Mode configuration only when the recorder is
    /// in an "active" state that should expose context to the user — recording,
    /// liveText, transcribing, enhancing. `.done` / `.failed` / `.hidden`
    /// suppress the pill so it doesn't pollute the post-action card slot.
    private func activePowerModeForPhase(_ phase: HaloPhase) -> PowerModeConfig? {
        switch phase {
        case .recording, .liveText, .transcribing, .enhancing:
            return powerModeManager.activeConfiguration
        case .hidden, .armed, .done, .failed:
            return nil
        }
    }

    // MARK: - Transitions (spec §2.4 sequencing)
    //
    // Each transition carries its OWN animation via `.animation(_:)` on the
    // transition value. That's how you encode per-element delays in SwiftUI
    // without spawning DispatchQueue timers — the transition's animation
    // overrides the ambient one for its insertion / removal pass.

    private var orbTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.85))
                .animation(.haloExpand),                 // t = 0.00
            removal: .opacity.animation(.haloCollapse)
        )
    }

    private var chipTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .animation(.haloExpand.delay(0.06)),     // t = 0.06
            removal: .opacity.animation(.haloCollapse)
        )
    }

    private var cardTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: -8)
                .combined(with: .opacity)
                .animation(.haloExpand.delay(0.09)),     // t = 0.09
            removal: .opacity
                .combined(with: .scale(scale: 0.92))
                .animation(.haloCollapse)
        )
    }

    // MARK: - Phase derivation
    //
    // Map engine `RecordingState` → view `HaloPhase`. `.done` is synthesized
    // here from the 1s dwell window after a fresh `lastPasteEvent`.

    private var derivedPhase: HaloPhase {
        // `.done` synthesis wins over the engine state for the 1s window —
        // the engine has typically already moved on to `.idle` by the time
        // the paste fires.
        if doneActive { return .done }

        switch stateProvider.recordingState {
        case .idle:
            return .hidden
        case .starting:
            return .recording
        case .recording:
            // Preserve v1: liveText sub-state when partial transcript is
            // non-empty AND the user has the toggle on. ConstellationCard
            // shares content for `.recording` / `.liveText`, so the visible
            // difference is mostly the orb pulse continuing through.
            if showLiveTextPreview && !stateProvider.partialTranscript.isEmpty {
                return .liveText
            }
            return .recording
        case .transcribing:
            return .transcribing
        case .enhancing:
            return .enhancing
        case .busy:
            // v1 behavior — collapse on `.busy`. Plan parenthetical confirms.
            return .hidden
        case .failed:
            return .failed
        }
    }

    // MARK: - Done-state dwell handling

    private func handleLastPasteEvent(_ event: PasteEvent?) {
        guard event != nil else { return }
        // Cancel any in-flight 1s window so back-to-back pastes restart the
        // dwell rather than terminate it early.
        doneTask?.cancel()
        doneActive = true

        doneTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            doneActive = false
        }
    }

    // MARK: - Breathe pulse (spec §2.4 / §2.3)

    /// 0…1 sine ramped at `phase` only when `.enhancing`. Static 0.5 under
    /// Reduce Motion so the sheen still renders, just without the pulse.
    private func breathePulse(at date: Date) -> Double {
        guard derivedPhase == .enhancing else { return 0 }
        if AccessibilityMotionMonitor.shared.reduceMotion { return 0.5 }
        // 1.6s full period — matches CardBreath / spec §2.3.
        let t = date.timeIntervalSinceReferenceDate
        let theta = (t.truncatingRemainder(dividingBy: 1.6) / 1.6) * 2.0 * .pi
        return (sin(theta) * 0.5) + 0.5
    }

    // MARK: - Card content sources

    private var activePromptIcon: String {
        // `PromptIcon` is `typealias PromptIcon = String` — the raw SF Symbol
        // name lives directly on `.icon`. Empty string (defensive) → fall
        // back to the default `sparkles` glyph.
        let raw = stateProvider.enhancementService?.activePrompt?.icon ?? "sparkles"
        return raw.isEmpty ? "sparkles" : raw
    }

    private var activePromptName: String {
        stateProvider.enhancementService?.activePrompt?.title ?? "Default Mode"
    }

    private var transcriptionEngineLabel: String {
        stateProvider.transcriptionModelLabel ?? "WHISPER · LARGE-V3"
    }

    private var enhancementProviderLabel: String {
        let provider = providerShortName(aiService.selectedProvider)
        let model = compactModelName(aiService.currentModel)
        return model.isEmpty ? provider : "\(provider) · \(model)"
    }

    // MARK: - Provider / model label helpers
    //
    // Migrated verbatim from the v1 `EnhancingIdentity` helpers in
    // HaloRecorderView so chip + card share canonical labels. Keep these
    // file-local so we don't accidentally widen the surface.

    private func providerShortName(_ p: AIProvider) -> String {
        switch p {
        case .openAI:           return "OPENAI"
        case .anthropic:        return "CLAUDE"
        case .gemini:           return "GEMINI"
        case .groq:             return "GROQ"
        case .cerebras:         return "CEREBRAS"
        case .openRouter:       return "OPENROUTER"
        case .mistral:          return "MISTRAL"
        case .ollama:           return "OLLAMA"
        case .localCLI:         return "LOCAL CLI"
        case .foundationModels: return "APPLE"
        case .mlx:              return "MLX"
        case .custom:           return "CUSTOM"
        case .elevenLabs, .deepgram, .soniox, .speechmatics:
            return p.rawValue.uppercased()
        }
    }

    private func compactModelName(_ raw: String) -> String {
        var s = raw
        if let slash = s.lastIndex(of: "/") {
            s = String(s[s.index(after: slash)...])
        }
        if s.hasPrefix("models/") { s.removeFirst("models/".count) }
        return s.uppercased()
    }
}

// MARK: - ConstellationLayout
//
// Per-mode geometry. Orchestrator uses absolute `.position()` for each
// satellite over a panel sized full-screen-width × 120pt; `cardCenterY`
// is computed from the notch baseline + 12pt padding + half the card's
// nominal 56pt height so a 56pt card centers its top edge 12pt below
// the notch (spec §3.1 layout diagram).

struct ConstellationLayout {
    /// True when the active screen reports a physical safe-area inset (i.e.
    /// the notched MacBook displays). Drives the layout split between
    /// "flank-the-notch" (notch mode) and "centered virtual notch"
    /// (floating mode).
    let isNotched: Bool
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let screenWidth: CGFloat

    /// Card nominal height — used to center the card vertically. Matches
    /// `ConstellationCard.cardMinHeight` in spec §3.1.
    static let cardNominalHeight: CGFloat = 56
    static let cardTopGap: CGFloat = 12

    static func current(mode: HaloShape.Mode) -> ConstellationLayout {
        guard let screen = NSScreen.main else {
            return ConstellationLayout(
                isNotched: false,
                notchHeight: 24,
                notchWidth: 0,
                screenWidth: 1440
            )
        }
        let safeTop = screen.safeAreaInsets.top
        let isNotched = safeTop > 0
        let notchHeight: CGFloat = isNotched
            ? safeTop
            : NSStatusBar.system.thickness
        let notchWidth: CGFloat = {
            if let l = screen.auxiliaryTopLeftArea?.width,
               let r = screen.auxiliaryTopRightArea?.width {
                return screen.frame.width - l - r
            }
            return 180
        }()
        return ConstellationLayout(
            isNotched: isNotched && mode == .notch,
            notchHeight: notchHeight,
            notchWidth: notchWidth,
            screenWidth: screen.frame.width
        )
    }

    /// Orb x — notch mode flanks the physical notch at ~26%, floating mode
    /// flanks a virtual notch ~100pt left of center.
    var orbX: CGFloat {
        isNotched
            ? screenWidth * 0.26
            : (screenWidth / 2) - 100
    }

    /// Chip x — mirror of orbX.
    var chipX: CGFloat {
        isNotched
            ? screenWidth * 0.74
            : (screenWidth / 2) + 100
    }

    /// Satellite y — vertically centered on the menu-bar / notch row.
    var satelliteY: CGFloat {
        notchHeight / 2
    }

    /// Card center x — always horizontally centered on the screen, both
    /// notch and floating modes.
    var cardCenterX: CGFloat {
        screenWidth / 2
    }

    /// Card center y — 12pt below the notch baseline + half the nominal
    /// card height. Matches the spec §3.1 layout diagram (card top edge at
    /// notch baseline + 12pt).
    var cardCenterY: CGFloat {
        notchHeight + Self.cardTopGap + (Self.cardNominalHeight / 2)
    }

    /// Whisper line y — sits 12pt below the notch baseline (same row as
    /// the card top edge) so on idle the line replaces the absent card.
    var whisperY: CGFloat {
        notchHeight + Self.cardTopGap
    }
}
