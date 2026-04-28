import SwiftUI

// MARK: - PromptLivePreview
//
// Right pane of the Prompt Editor split (spec §3.9 / plan §P3.E). Edits to
// the prompt body re-trigger an enhancement run on a fixed example transcript
// after a 1.2s debounce. In-flight runs are pre-empted by re-edits via `Task`
// cancellation — only one enhancement can be visible at a time, and no leaked
// tasks update state after a newer edit lands.
//
// Status grammar matches the Constellation pipeline (spec §2.2):
//   - tangerine (`Palette.accent`) + `haloBreathOrb` while enhancing
//   - green flash (`Palette.success`) + scale keyframe on result
//   - tangerine (`Palette.accent`) on failure — motion distinguishes from enhancing
//   - neutral grey idle / debouncing
//
// Reduce Motion (via `AccessibilityMotionMonitor`) collapses the dot to a
// static color swap — no breath, no scale flash.
//
// The "Auto-run" toggle in the header gates the debounce pump entirely
// (mitigation for plan §P3.E API-cost risk note — prevents an LLM call on
// every keystroke pause while drafting).
struct PromptLivePreview: View {
    let prompt: CustomPrompt
    var exampleInput: String = Self.defaultExampleInput
    @ObservedObject var aiService: AIService
    @ObservedObject var enhancementService: AIEnhancementService

    @ObservedObject private var motion = AccessibilityMotionMonitor.shared

    @State private var liveEnabled: Bool = true
    @State private var output: String = ""
    @State private var phase: Phase = .idle
    @State private var errorMessage: String? = nil
    /// Single combined pump task for both debounce sleep + enhancement call.
    /// Cancelling this one handle pre-empts whichever stage is active —
    /// satisfies "no overlapping calls / no leaked tasks" (plan §P3.E).
    @State private var pumpTask: Task<Void, Never>? = nil
    @State private var greenFlashTrigger: Int = 0

    enum Phase: Equatable {
        case idle, debouncing, enhancing, done, failed
    }

    /// Hardcoded debounce duration. Spec §3.9 / plan §P3.E acceptance criteria
    /// require **exactly 1.2s**, not "around 1s". Reviewer note: this is the
    /// only knob and it is not configurable at the call site.
    static let debounceSeconds: TimeInterval = 1.2

    /// Stock 1-paragraph fragment with um/like/yknow disfluencies — exercises
    /// the prompt's cleanup behavior so users can eyeball the diff.
    static let defaultExampleInput =
        "umm so the dynamic island feels great when you're like multitasking " +
        "but i think the haptics could be a little less aggressive y'know"

    // MARK: - Body

    var body: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider().opacity(0.4)
                exampleSection
                Divider().opacity(0.4)
                outputSection
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onChange(of: prompt.promptText) { _, _ in scheduleRun() }
        .onChange(of: prompt.useSystemInstructions) { _, _ in scheduleRun() }
        .onChange(of: aiService.selectedProvider) { _, _ in scheduleRun() }
        .onChange(of: aiService.currentModel) { _, _ in scheduleRun() }
        .onChange(of: liveEnabled) { _, on in
            if on { scheduleRun() } else { cancelRun(reset: false) }
        }
        .onAppear { scheduleRun() }
        .onDisappear { cancelRun(reset: true) }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            statusDot
            Text("Live Preview")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Text(phaseLabel)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .animation(motion.reduceMotion ? nil : .haloPhaseCrossfade, value: phaseLabel)

            Spacer()

            HStack(spacing: 6) {
                Text(liveEnabled ? "Auto-run" : "Paused")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Toggle(isOn: $liveEnabled) { EmptyView() }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            .help(liveEnabled
                  ? "Pause live preview to stop auto-runs while editing."
                  : "Resume live preview.")
        }
    }

    private var phaseLabel: String {
        switch phase {
        case .idle:        return liveEnabled ? "idle" : "paused"
        case .debouncing:  return "settling…"
        case .enhancing:   return "enhancing…"
        case .done:        return "ready"
        case .failed:      return "failed"
        }
    }

    private var exampleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Example input")
            Text(exampleInput)
                .font(.system(.body))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Enhanced output")
            outputBody
        }
    }

    @ViewBuilder
    private var outputBody: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.system(.body))
                .foregroundColor(Palette.accent)
                .fixedSize(horizontal: false, vertical: true)
        } else if output.isEmpty {
            Text(emptyPlaceholder)
                .font(.system(.body))
                .foregroundStyle(.tertiary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(output)
                .font(.system(.body))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var emptyPlaceholder: String {
        switch phase {
        case .idle where !liveEnabled: return "Live preview is paused. Toggle Auto-run to resume."
        case .idle:                    return "Edit the prompt to see how the example transcript gets enhanced."
        case .debouncing:              return "Settling — running in 1.2s…"
        case .enhancing:               return "Running enhancement…"
        case .done:                    return ""
        // Defensive — if we ever land in `.failed` with `errorMessage == nil`
        // (shouldn't happen via `runEnhancement`, but the state machine has
        // two independent fields), surface a generic message instead of an
        // empty pane (reviewer-p3e edge case nit).
        case .failed:                  return "Enhancement failed. Edit the prompt to retry."
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.06 * 10)
            .foregroundStyle(.secondary)
    }

    // MARK: - Status dot — Constellation grammar

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 9, height: 9)
            // Violet breathing while enhancing — re-uses the canonical
            // enhancing-orb token. Reduce Motion → static.
            .haloBreathOrb(active: phase == .enhancing && !motion.reduceMotion)
            // One-shot scale flash on `.done`. Reduce Motion → no scale change
            // (keyframes collapse to 1.0 → 1.0 → 1.0), color swap remains.
            .keyframeAnimator(initialValue: 1.0, trigger: greenFlashTrigger) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                LinearKeyframe(1.0, duration: 0.0)
                LinearKeyframe(motion.reduceMotion ? 1.0 : 1.7, duration: 0.18)
                LinearKeyframe(1.0, duration: 0.34)
            }
            .animation(motion.reduceMotion ? nil : .haloPhaseCrossfade, value: dotColor)
            .accessibilityLabel("Preview status: \(phaseLabel)")
    }

    private var dotColor: Color {
        switch phase {
        case .idle, .debouncing: return Palette.neutral
        case .enhancing:         return Palette.accent
        case .done:              return Palette.success
        case .failed:            return Palette.accent
        }
    }

    // MARK: - Debounce + cancellation pump

    /// Schedule a debounced enhancement run for the current `prompt`
    /// snapshot. Cancels any prior pump (debounce sleep OR in-flight
    /// enhancement) before scheduling — only one run can ever be live.
    private func scheduleRun() {
        guard liveEnabled else { return }
        let trimmed = prompt.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelRun(reset: true)
            return
        }
        // Pre-empt prior pump — covers both the debounce sleep and any
        // in-flight URLSession request inside the enhancement call.
        pumpTask?.cancel()
        phase = .debouncing
        let snapshot = prompt
        let input = exampleInput
        pumpTask = Task { @MainActor in
            let nanos = UInt64(Self.debounceSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await runEnhancement(snapshot: snapshot, input: input)
        }
    }

    /// Cancel any pending debounce or in-flight enhancement. When `reset`
    /// is true, also clear displayed output and error state.
    private func cancelRun(reset: Bool) {
        pumpTask?.cancel()
        pumpTask = nil
        if reset {
            phase = .idle
            output = ""
            errorMessage = nil
        } else if phase == .debouncing || phase == .enhancing {
            phase = .idle
        }
    }

    @MainActor
    private func runEnhancement(snapshot: CustomPrompt, input: String) async {
        guard enhancementService.isConfigured else {
            phase = .failed
            errorMessage = "AI provider not configured. Add an API key in AI settings."
            return
        }
        phase = .enhancing
        errorMessage = nil
        do {
            let result = try await enhancementService.enhancePreview(
                text: input,
                prompt: snapshot
            )
            // Re-check cancellation on resume — a newer edit may have
            // cancelled this Task between the await and now.
            guard !Task.isCancelled else { return }
            output = result
            phase = .done
            greenFlashTrigger &+= 1
        } catch is CancellationError {
            // Pre-empted by a newer edit. Drop the result silently — the
            // newer pump will own the displayed state.
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
