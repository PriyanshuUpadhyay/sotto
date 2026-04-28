import SwiftUI
import AppKit

// MARK: - ConstellationCard (legacy)
//
// Pre-W2 Constellation card. Retained ONLY for `CinematicWalkthrough.swift`
// (onboarding, deferred per spec §5). The live recorder uses
// `ConstellationCluster` + `ChipPanel` instead. Do not add new consumers.
//
// Floating Adaptive Glass card — third satellite of the Constellation recorder
// (spec §3.1). Fixed 280pt wide × dynamic height (≥ 56pt), 22pt corner radius.
// Phase-driven content per the §3.1 phase content table.
//
// Phase contract (spec §3.1):
//   .hidden / .armed         → card removed from layout (zero-opacity). The
//                              engine-side `RecordingState.idle` is mapped to
//                              `.hidden` by the orchestrator (see
//                              RecorderStateProvider) — `HaloPhase` has no
//                              `.idle` case.
//   .recording               → live transcript via StreamingCaretTranscript
//                              (which already renders its own blinking caret).
//                              Static card.
//   .liveText                → same as .recording (engine emits .liveText when
//                              a partial transcript is present; orchestrator
//                              maps to the same content).
//   .transcribing            → waveform.badge.magnifyingglass + Display
//                              "Transcribing" + Mono transcriptionEngineLabel.
//                              Cyan shimmer sweep across card every 1.6s.
//   .enhancing               → activePromptIcon + Display
//                              "Enhancing with <activePromptName>" + Mono
//                              enhancementProviderLabel. Card breath
//                              scale 1.0↔1.012 / 1.6s.
//   .done                    → checkmark.circle.fill + Display
//                              "Pasted to <pasteTargetAppName ?? clipboard>"
//                              + Body italic 13pt donePreview (1-line trunc.).
//                              Static, dwell managed by orchestrator.
//   .failed                  → exclamationmark.triangle.fill + Display
//                              "Transcription failed" / "Enhancement failed"
//                              (branched on failureReason content) +
//                              Body 13pt recovery hint.
//
// Motion contract (spec §3.1, §2.4):
//   Drop-in   → translateY(-8→0) + opacity(0→1) on `Animation.haloExpand`.
//   Exit      → opacity + scale(0.92) on `Animation.haloCollapse`.
//   Phase swap→ opacity + scale(0.96→1) on `Animation.haloPhaseCrossfade`.
//
// Reduce Motion (spec §6.4):
//   Drop-in collapses to immediate fade. Shimmer + breath swap to static
//   color tint (HaloShimmer / inline breath modifier already honor
//   AccessibilityMotionMonitor).

struct ConstellationCard: View {
    let phase: HaloPhase
    var partialTranscript: String = ""
    var pasteTargetAppName: String? = nil
    var donePreview: String? = nil
    var failureReason: String? = nil
    var activePromptIcon: String = "sparkles"
    var activePromptName: String = "Default Mode"
    var transcriptionEngineLabel: String = "WHISPER · LARGE-V3"
    var enhancementProviderLabel: String = "CLAUDE · SONNET-4-6"
    var appearance: GlassAppearance = .onyx

    /// Drives the spec §2.3 layer-6 violet inner sheen on the underlying
    /// `HaloMaterial`. The orchestrator (P1.G) sets this to
    /// `phase == .enhancing` so the sheen renders only during the enhancing
    /// state — replaces the placeholder `false` previously hard-coded here
    /// (P1.F reviewer carry-over).
    var showInnerSheen: Bool = false
    /// 0…1 sine ramp synced to the 1.6s breath. Fed into HaloMaterial layer-6
    /// to modulate sheen intensity. Caller drives — the card itself stays
    /// stateless about the breath phase. Reduce Motion: orchestrator should
    /// pin this to a static mid-value.
    var breathePulse: Double = 0

    @ObservedObject private var motion = AccessibilityMotionMonitor.shared

    // MARK: - Layout constants (spec §3.1)
    private static let cardWidth: CGFloat = 280
    private static let cardMinHeight: CGFloat = 56
    private static let cornerRadius: CGFloat = 22
    private static let horizontalPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 10
    private static let iconColumnWidth: CGFloat = 24
    private static let leadingIconSize: CGFloat = 18

    // Available width for the streaming transcript inside the card. Card
    // width minus horizontal padding both sides minus the +8pt fudge that
    // `StreamingCaretTranscript` adds to its outer frame internally.
    private static let transcriptMaxWidth: CGFloat =
        cardWidth - (horizontalPadding * 2) - 8

    var body: some View {
        ZStack {
            if isVisible {
                cardBody
                    .transition(visibilityTransition)
            }
        }
        .frame(width: Self.cardWidth, alignment: .center)
        // Asymmetric per-direction animation: drop-in via `.haloExpand`,
        // exit via `.haloCollapse`. Reduce Motion → no animation, transition
        // collapses to an instant fade.
        .animation(
            motion.reduceMotion
                ? .linear(duration: 0)
                : (isVisible ? .haloExpand : .haloCollapse),
            value: isVisible
        )
    }

    // MARK: - Visibility

    private var isVisible: Bool {
        switch phase {
        case .hidden, .armed: return false
        case .recording, .liveText, .transcribing, .enhancing, .done, .failed:
            return true
        }
    }

    private var visibilityTransition: AnyTransition {
        if motion.reduceMotion {
            // Reduce Motion → drop-in becomes immediate fade (spec §6.4).
            return .opacity
        }
        return .asymmetric(
            insertion: .offset(y: -8).combined(with: .opacity),
            removal: .opacity.combined(with: .scale(scale: 0.92))
        )
    }

    // MARK: - Card body

    private var cardBody: some View {
        ZStack {
            // Material — onyx / light glass sheet. Sheen + breathe pulse
            // are driven by the orchestrator (P1.G) so the spec §2.3 layer-6
            // violet inner sheen renders during `.enhancing` only.
            HaloMaterial(
                shape: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous),
                phase: phase,
                breathePulse: breathePulse,
                showInnerSheen: showInnerSheen,
                appearance: appearance
            )

            // Phase-keyed content. Crossfade with scale 0.96 → 1.0 over
            // 0.22s `.haloPhaseCrossfade` between phases (spec §3.1).
            phaseContent
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, Self.verticalPadding)
                .frame(width: Self.cardWidth, alignment: .leading)
                .id(contentID)
                .transition(
                    .opacity.combined(with: .scale(scale: 0.96))
                )

            // Cyan shimmer sweep — `.transcribing` only. Clipped to card
            // shape so the gradient doesn't bleed past the silhouette.
            // Reduce Motion → HaloShimmer freezes at mid-phase, so this
            // becomes a static cyan tint (spec §6.4).
            if phase == .transcribing {
                shimmerOverlay
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Self.cardWidth)
        .frame(minHeight: Self.cardMinHeight, alignment: .center)
        .modifier(CardBreath(active: phase == .enhancing))
        .animation(.haloPhaseCrossfade, value: contentID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// Stable identity for the crossfade — recording + liveText share a single
    /// id so the live caret view is preserved across micro-state flips and
    /// doesn't re-animate on every partial-transcript chunk. Other phases keep
    /// their own ids so the crossfade fires on real phase changes.
    private var contentID: String {
        switch phase {
        case .recording, .liveText: return "recording"
        case .hidden:               return "hidden"
        case .armed:                return "armed"
        case .transcribing:         return "transcribing"
        case .enhancing:            return "enhancing"
        case .done:                 return "done"
        case .failed:               return "failed"
        }
    }

    // MARK: - Phase content

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .recording, .liveText:
            recordingContent
        case .transcribing:
            transcribingContent
        case .enhancing:
            enhancingContent
        case .done:
            doneContent
        case .failed:
            failedContent
        case .hidden, .armed:
            // Card hidden at this layer; isVisible already gates the body.
            EmptyView()
        }
    }

    private var recordingContent: some View {
        // `StreamingCaretTranscript` already paints its own BlinkingCaret —
        // the spec table's "+ blinking caret" describes that built-in caret.
        // Do not add a second caret here (reviewer focus).
        StreamingCaretTranscript(
            text: partialTranscript,
            maxWidth: Self.transcriptMaxWidth
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transcribingContent: some View {
        twoLineRow(
            icon: "waveform.badge.magnifyingglass",
            iconColor: Palette.accent,
            displayText: "Transcribing",
            monoText: transcriptionEngineLabel
        )
    }

    private var enhancingContent: some View {
        twoLineRow(
            icon: activePromptIcon,
            iconColor: Palette.accent,
            displayText: "Enhancing with \(activePromptName)",
            monoText: enhancementProviderLabel
        )
    }

    private var doneContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Self.leadingIconSize, weight: .semibold))
                .foregroundStyle(Palette.success)
                .frame(width: Self.iconColumnWidth, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("Pasted to \(pasteTargetAppName ?? "clipboard")")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let preview = donePreview, !preview.isEmpty {
                    Text("\u{201C}\(preview)\u{201D}")
                        .font(.system(size: 13, weight: .regular, design: .default).italic())
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var failedContent: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Self.leadingIconSize, weight: .semibold))
                .foregroundStyle(Palette.warn)
                .frame(width: Self.iconColumnWidth, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(failureTitle)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(failureHint)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// Shared icon + display + mono row used by `.transcribing` and
    /// `.enhancing`. Mono row tracking matches the chip — 1.4 tracking,
    /// all-caps, 9pt SF Mono medium (spec §2.2).
    private func twoLineRow(
        icon: String,
        iconColor: Color,
        displayText: String,
        monoText: String
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: Self.leadingIconSize, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: Self.iconColumnWidth, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayText)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(monoText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Failure parsing

    private var failureTitle: String {
        let reason = (failureReason ?? "").lowercased()
        if reason.contains("enhanc") {
            return "Enhancement failed"
        }
        return "Transcription failed"
    }

    private var failureHint: String {
        if let reason = failureReason, !reason.isEmpty {
            return reason
        }
        return "Try again or check Settings"
    }

    // MARK: - Shimmer overlay (transcribing)

    private var shimmerOverlay: some View {
        HaloShimmer(period: 1.6) { phaseT in
            // Diagonal-ish horizontal sweep — width-2 highlight band that
            // travels across the card. Cyan at peak, transparent at edges.
            // Under Reduce Motion HaloShimmer pins phaseT = 0.5, so the band
            // sits centered as a static tint.
            GeometryReader { geo in
                let bandWidth: CGFloat = max(48, geo.size.width * 0.32)
                let travel: CGFloat = geo.size.width + bandWidth
                let xCenter: CGFloat = -bandWidth / 2 + CGFloat(phaseT) * travel
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Palette.accent.opacity(0.32), location: 0.5),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: bandWidth, height: geo.size.height)
                .blendMode(.plusLighter)
                .position(x: xCenter + bandWidth / 2, y: geo.size.height / 2)
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        switch phase {
        case .hidden, .armed:
            return ""
        case .recording, .liveText:
            let trimmed = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Recording, awaiting transcript"
                : "Recording: \(trimmed)"
        case .transcribing:
            return "Transcribing using \(humanReadable(transcriptionEngineLabel))"
        case .enhancing:
            return "Enhancing with \(activePromptName) using \(humanReadable(enhancementProviderLabel))"
        case .done:
            let target = pasteTargetAppName ?? "clipboard"
            if let preview = donePreview, !preview.isEmpty {
                return "Pasted to \(target). Preview: \(preview)"
            }
            return "Pasted to \(target)"
        case .failed:
            return "\(failureTitle). \(failureHint)"
        }
    }

    /// Best-effort prettifier for the mono labels (e.g.
    /// "CLAUDE · SONNET-4-6" → "Claude Sonnet 4 6") so VoiceOver reads them
    /// as words instead of letter-by-letter.
    private func humanReadable(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "·", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.lowercased().capitalized }
            .joined(separator: " ")
    }
}

// MARK: - CardBreath
//
// Inline breath modifier — sibling of `HaloBreathOrb` (`Animation+Halo.swift`)
// but scaled to spec §3.1 card amplitude `1.0 ↔ 1.012` over 1.6s. Pattern is
// identical: `@State raised`, `@ObservedObject motion`, animation gated on
// `active && !reduceMotion`. Reduce Motion / inactive → frozen at 1.0.

private struct CardBreath: ViewModifier {
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    var active: Bool

    @State private var raised: Bool = false

    private static let halfPeriod: TimeInterval = 0.8  // 1.6s full cycle (spec §3.1)
    private static let peak: CGFloat = 1.012

    private var shouldAnimate: Bool { active && !motion.reduceMotion }

    func body(content: Content) -> some View {
        content
            .scaleEffect(raised ? Self.peak : 1.0)
            .animation(
                shouldAnimate
                    ? .easeInOut(duration: Self.halfPeriod).repeatForever(autoreverses: true)
                    : nil,
                value: raised
            )
            .onAppear { raised = shouldAnimate }
            .onChange(of: shouldAnimate) { _, animate in raised = animate }
    }
}

// MARK: - Previews
//
// Cycles through all six visible phases (plus an `.idle` no-op state for
// completeness). On first launch the card drops in via `.haloExpand`; the
// "Cycle phases" button advances through the table so the reviewer can see
// the 0.22s `.haloPhaseCrossfade` content swap and the breath / shimmer
// motion tokens in situ.

#if DEBUG
private struct ConstellationCardPreviewHarness: View {
    @State private var phase: HaloPhase = .hidden
    @State private var index: Int = 0

    // Cycle order matches spec §3.1 phase content table — `.hidden` stands
    // in for "idle" (HaloPhase has no `.idle` case; orchestrator maps engine
    // idle → `.hidden`). `.liveText` is omitted from the cycle because it
    // shares a content slot with `.recording`.
    private let cycle: [HaloPhase] = [
        .hidden, .recording, .transcribing, .enhancing, .done, .failed
    ]

    private var failureReason: String? {
        switch phase {
        case .failed: return "Enhancement failed: check API key in Settings"
        default:      return nil
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            ConstellationCard(
                phase: phase,
                partialTranscript: phase == .recording
                    ? "the dynamic island feels great when satellites appear"
                    : "",
                pasteTargetAppName: "Cursor",
                donePreview: "Sure, here's the dynamic island idea",
                failureReason: failureReason,
                activePromptIcon: "sparkles",
                activePromptName: "Default Mode",
                transcriptionEngineLabel: "WHISPER · LARGE-V3",
                enhancementProviderLabel: "CLAUDE · SONNET-4-6",
                appearance: .onyx
            )

            HStack(spacing: 12) {
                Button("Cycle phases") {
                    index = (index + 1) % cycle.count
                    phase = cycle[index]
                }
                Text("phase: \(String(describing: phase))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(width: 480)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
    }
}

#Preview("ConstellationCard — phase cycle") {
    ConstellationCardPreviewHarness()
}

#Preview("ConstellationCard — recording (live)") {
    ConstellationCard(
        phase: .recording,
        partialTranscript: "the dynamic island feels great when satellites appear",
        appearance: .onyx
    )
    .padding(40)
    .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("ConstellationCard — transcribing") {
    ConstellationCard(
        phase: .transcribing,
        transcriptionEngineLabel: "WHISPER · LARGE-V3",
        appearance: .onyx
    )
    .padding(40)
    .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("ConstellationCard — enhancing") {
    ConstellationCard(
        phase: .enhancing,
        activePromptIcon: "sparkles",
        activePromptName: "Default Mode",
        enhancementProviderLabel: "CLAUDE · SONNET-4-6",
        appearance: .onyx
    )
    .padding(40)
    .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("ConstellationCard — done") {
    ConstellationCard(
        phase: .done,
        pasteTargetAppName: "Cursor",
        donePreview: "Sure, here's the dynamic island idea",
        appearance: .onyx
    )
    .padding(40)
    .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("ConstellationCard — failed (transcription)") {
    ConstellationCard(
        phase: .failed,
        failureReason: "Audio device unavailable. Try reconnecting your mic.",
        appearance: .onyx
    )
    .padding(40)
    .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("ConstellationCard — failed (enhancement)") {
    ConstellationCard(
        phase: .failed,
        failureReason: "Enhancement failed: check API key in Settings",
        appearance: .onyx
    )
    .padding(40)
    .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("ConstellationCard — light glass") {
    ConstellationCard(
        phase: .enhancing,
        activePromptIcon: "sparkles",
        activePromptName: "Default Mode",
        enhancementProviderLabel: "CLAUDE · SONNET-4-6",
        appearance: .light
    )
    .padding(40)
    .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
