import SwiftUI

// MARK: - ClusterChips
//
// Per-state factories that produce `[ChipDescriptor]` for the cluster.
// Each factory returns the chips in VoiceOver-priority order:
// anchor → reason (failure only) → secondaries → actions.
//
// Spec §4 chip slate:
//   recording   : REC + meter, TIME, PROMPT
//   transcribing: TRANSCRIBING, MODEL
//   enhancing   : ENHANCING, PROMPT, MODEL
//   done        : PASTED → <app>
//   failed      : FAIL, reason, RETRY, OPEN SETTINGS

enum ClusterChips {
    static func chips(
        phase: ClusterPhase,
        recordingStartedAt: Date?,
        audioLevel: Float,
        promptIcon: String?,
        promptName: String?,
        transcriptionModelLabel: String?,
        enhancementProviderLabel: String?,
        onRetry: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) -> [ChipDescriptor] {
        let haloPhase = HaloPhase(clusterPhase: phase)
        switch phase {
        case .idle:
            return []
        case .recording:
            return recordingChips(
                startedAt: recordingStartedAt,
                audioLevel: audioLevel,
                promptIcon: promptIcon,
                promptName: promptName,
                haloPhase: haloPhase
            )
        case .transcribing:
            return transcribingChips(modelLabel: transcriptionModelLabel, haloPhase: haloPhase)
        case .enhancing:
            return enhancingChips(
                promptIcon: promptIcon,
                promptName: promptName,
                providerLabel: enhancementProviderLabel,
                haloPhase: haloPhase
            )
        case .done(let appName, _):
            return doneChips(appName: appName)
        case .failed(let reason):
            return failedChips(
                reason: reason,
                onRetry: onRetry,
                onOpenSettings: onOpenSettings,
                haloPhase: haloPhase
            )
        }
    }

    // MARK: - Recording

    private static func recordingChips(
        startedAt: Date?,
        audioLevel: Float,
        promptIcon: String?,
        promptName: String?,
        haloPhase: HaloPhase
    ) -> [ChipDescriptor] {
        var chips: [ChipDescriptor] = [
            ChipDescriptor(
                id: "rec-anchor",
                kind: .anchor,
                motion: .ringPulseFast,
                axLabel: "Recording, level \(percent(audioLevel))"
            ) {
                AnchorChip(
                    label: "REC",
                    dotColor: haloPhase.glowColor,
                    rate: .fast,
                    haloPhase: haloPhase,
                    trailing: AnyView(MeterBars(level: audioLevel))
                )
            }
        ]

        if let startedAt {
            chips.append(
                ChipDescriptor(
                    id: "rec-time",
                    side: .left,
                    axLabel: "Elapsed time"
                ) {
                    TimeChip(startedAt: startedAt)
                }
            )
        }

        if let promptName, !promptName.isEmpty {
            chips.append(
                ChipDescriptor(
                    id: "rec-prompt",
                    side: .right,
                    axLabel: "Prompt \(promptName)"
                ) {
                    KeyValueChip(
                        key: "PROMPT",
                        value: promptName,
                        leadingSymbol: promptIcon
                    )
                }
            )
        }

        return chips
    }

    // MARK: - Transcribing

    private static func transcribingChips(modelLabel: String?, haloPhase: HaloPhase) -> [ChipDescriptor] {
        var chips: [ChipDescriptor] = [
            ChipDescriptor(
                id: "trans-anchor",
                kind: .anchor,
                motion: .shimmer,
                axLabel: "Transcribing"
            ) {
                AnchorChip(
                    label: "TRANSCRIBING",
                    dotColor: Palette.onyxFg.opacity(0.85),
                    rate: .none,
                    haloPhase: haloPhase
                )
                .chipShimmer(active: true)
            }
        ]

        if let modelLabel, !modelLabel.isEmpty {
            chips.append(
                ChipDescriptor(
                    id: "trans-model",
                    side: .right,
                    axLabel: "Model \(modelLabel)"
                ) {
                    KeyValueChip(key: "MODEL", value: modelLabel)
                }
            )
        }
        return chips
    }

    // MARK: - Enhancing

    private static func enhancingChips(
        promptIcon: String?,
        promptName: String?,
        providerLabel: String?,
        haloPhase: HaloPhase
    ) -> [ChipDescriptor] {
        var chips: [ChipDescriptor] = [
            ChipDescriptor(
                id: "enh-anchor",
                kind: .anchor,
                motion: .breath,
                axLabel: "Enhancing"
            ) {
                AnchorChip(
                    label: "ENHANCING",
                    dotColor: haloPhase.glowColor,
                    rate: .slow,
                    haloPhase: haloPhase
                )
            }
        ]

        if let promptName, !promptName.isEmpty {
            chips.append(
                ChipDescriptor(
                    id: "enh-prompt",
                    side: .left,
                    axLabel: "Prompt \(promptName)"
                ) {
                    KeyValueChip(
                        key: "PROMPT",
                        value: promptName,
                        leadingSymbol: promptIcon
                    )
                }
            )
        }
        if let providerLabel, !providerLabel.isEmpty {
            chips.append(
                ChipDescriptor(
                    id: "enh-model",
                    side: .right,
                    axLabel: "Model \(providerLabel)"
                ) {
                    KeyValueChip(key: "MODEL", value: providerLabel)
                }
            )
        }
        return chips
    }

    // MARK: - Done

    private static func doneChips(appName: String?) -> [ChipDescriptor] {
        let target = appName ?? "clipboard"
        return [
            ChipDescriptor(
                id: "done-anchor",
                kind: .anchor,
                motion: .none,
                axLabel: "Pasted to \(target)"
            ) {
                DoneAnchorChip(appName: target)
            }
        ]
    }

    // MARK: - Failed

    private static func failedChips(
        reason: String?,
        onRetry: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        haloPhase: HaloPhase
    ) -> [ChipDescriptor] {
        var chips: [ChipDescriptor] = [
            ChipDescriptor(
                id: "fail-anchor",
                kind: .anchor,
                motion: .ringPulseFast,
                axLabel: "Failed"
            ) {
                AnchorChip(
                    label: "FAIL",
                    dotColor: haloPhase.glowColor,
                    rate: .fast,
                    haloPhase: haloPhase
                )
            }
        ]

        if let reason, !reason.isEmpty {
            chips.append(
                ChipDescriptor(
                    id: "fail-reason",
                    side: .right,
                    axLabel: reason
                ) {
                    ReasonChip(text: reason)
                }
            )
        }

        chips.append(
            ChipDescriptor(
                id: "fail-retry",
                kind: .action,
                row: .action,
                axLabel: "Retry"
            ) {
                ActionChip(label: "RETRY", action: onRetry)
            }
        )
        chips.append(
            ChipDescriptor(
                id: "fail-settings",
                kind: .action,
                row: .action,
                axLabel: "Open Settings"
            ) {
                ActionChip(label: "OPEN SETTINGS", action: onOpenSettings)
            }
        )
        return chips
    }

    // MARK: - Helpers

    private static func percent(_ level: Float) -> String {
        let v = max(0, min(1, level))
        return "\(Int(v * 100)) percent"
    }
}

// MARK: - Concrete chip subviews

private struct AnchorChip: View {
    let label: String
    let dotColor: Color
    let rate: RingPulseRate
    let haloPhase: HaloPhase
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 6) {
            RingPulseDot(color: dotColor, rate: rate)
            Text(label)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundStyle(Palette.onyxFg)
            if let trailing {
                trailing
            }
        }
        .recorderChip(phase: haloPhase)
    }
}

private struct KeyValueChip: View {
    let key: String
    let value: String
    var leadingSymbol: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let leadingSymbol, !leadingSymbol.isEmpty {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.onyxMute)
            }
            Text(key)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 9.5)
                .foregroundStyle(Palette.onyxMute)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundStyle(Palette.onyxFg)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .recorderChip(phase: .hidden)
    }
}

private struct TimeChip: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1.0)) { ctx in
            let elapsed = max(0, ctx.date.timeIntervalSince(startedAt))
            Text(format(elapsed))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundStyle(Palette.onyxFg)
                .recorderChip(phase: .hidden)
        }
    }

    private func format(_ s: TimeInterval) -> String {
        let total = Int(s)
        let m = total / 60
        let r = total % 60
        return String(format: "%02d:%02d", m, r)
    }
}

private struct MeterBars: View {
    let level: Float

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<4, id: \.self) { i in
                let threshold = Float(i + 1) / 4.0
                Capsule()
                    .fill(level >= threshold ? Palette.brandAcid : Palette.brandAcid.opacity(0.30))
                    .frame(width: 1.5, height: CGFloat(3 + i))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DoneAnchorChip: View {
    let appName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HaloPhase.done.glowColor)
            Text("PASTED")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundStyle(Palette.onyxFg)
            Text("\u{2192}")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.onyxMute)
            Text(appName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.onyxFg)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .recorderChip(phase: .done)
    }
}

private struct ReasonChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(Palette.onyxFg)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 280, alignment: .leading)
            .recorderChip(phase: .hidden)
    }
}

private struct ActionChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundStyle(Palette.onyxFg)
        }
        .buttonStyle(.plain)
        .recorderChip(phase: .hidden)
    }
}
