import SwiftUI

// MARK: - PromptChipPicker
//
// Horizontal scroller of 56×56pt prompt chips. Spec §3.2 "Prompt chips":
// rounded-square glass background, prompt icon + name. Selected chip carries
// a 2pt `Palette.enhance` ring (named token — reviewer focus, NOT a hex).
//
// Selection-change pulse — spec §4 "Provider chip glow on switch":
// the newly selected chip pulses a single time over 0.4s. Approach: the
// picker bumps a `pulseTrigger` UUID on `selectedID` change and forwards it
// to every chip; only the chip whose `id == selectedID` runs the pulse.
//
// Reduce Motion → no scale/shadow pulse; selection ring color change is the
// only feedback (immediate, no animation).
//
// VoiceOver → each chip is a button (`.isButton` trait), labelled with the
// prompt's title.

struct PromptChipPicker: View {
    let prompts: [CustomPrompt]
    @Binding var selectedID: UUID?

    @State private var pulseTrigger: UUID = UUID()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(prompts) { prompt in
                    PromptChip(
                        prompt: prompt,
                        isSelected: prompt.id == selectedID,
                        pulseTrigger: pulseTrigger
                    )
                    .onTapGesture { selectedID = prompt.id }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .onChange(of: selectedID) { _, _ in
            pulseTrigger = UUID()
        }
    }
}

// MARK: - PromptChip

private struct PromptChip: View {
    let prompt: CustomPrompt
    let isSelected: Bool
    let pulseTrigger: UUID

    @ObservedObject private var detector = GlassAppearanceDetector.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 3) {
            Image(systemName: prompt.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.primary)
                .frame(height: 24)
            Text(prompt.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 50)
        }
        .padding(.horizontal, 4)
        .frame(width: 56, height: 56)
        .background(
            HaloMaterial(
                shape: shape,
                phase: .hidden,
                appearance: detector.current
            )
        )
        .overlay(
            // Selection ring — 2pt named-token tint, NOT a hex (reviewer focus).
            shape.stroke(
                isSelected ? Palette.enhance : Color.clear,
                lineWidth: 2
            )
        )
        .modifier(
            PromptChipPulseModifier(
                triggerID: pulseTrigger,
                isSelected: isSelected
            )
        )
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(prompt.title)
    }
}

// MARK: - PromptChipPulseModifier
//
// Single 0.4s violet pulse driven by `triggerID` change. Reduce Motion
// short-circuits to a no-op (selection ring color change is the only
// feedback in that case).

private struct PromptChipPulseModifier: ViewModifier {
    let triggerID: UUID
    let isSelected: Bool

    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    @State private var phase: CGFloat = 0   // 0 → rest, 1 → peak

    private static let halfDuration: TimeInterval = 0.2

    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0 + 0.06 * phase)
            .shadow(
                color: Palette.enhance.opacity(0.55 * Double(phase)),
                radius: 18 * phase
            )
            .onChange(of: triggerID) { _, _ in
                guard isSelected, !motion.reduceMotion else { return }
                // Reset then ramp up; ramp down 200ms later. Total 0.4s.
                phase = 0
                withAnimation(.easeOut(duration: Self.halfDuration)) {
                    phase = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.halfDuration) {
                    withAnimation(.easeIn(duration: Self.halfDuration)) {
                        phase = 0
                    }
                }
            }
    }
}

// MARK: - Previews

#if DEBUG
private struct PromptChipPickerPreviewHarness: View {
    @State private var selectedID: UUID?

    private static let samplePrompts: [CustomPrompt] = [
        CustomPrompt(title: "Default", promptText: "", icon: "doc.text.fill"),
        CustomPrompt(title: "Email", promptText: "", icon: "envelope.fill"),
        CustomPrompt(title: "Code", promptText: "", icon: "curlybraces"),
        CustomPrompt(title: "Notes", promptText: "", icon: "note"),
        CustomPrompt(title: "Meeting", promptText: "", icon: "person.2.fill"),
        CustomPrompt(title: "Bullet List", promptText: "", icon: "list.bullet"),
        CustomPrompt(title: "Brainstorm", promptText: "", icon: "lightbulb.fill"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROMPT")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            PromptChipPicker(
                prompts: Self.samplePrompts,
                selectedID: $selectedID
            )
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { selectedID = Self.samplePrompts.first?.id }
    }
}

#Preview("Onyx") {
    PromptChipPickerPreviewHarness()
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Light") {
    PromptChipPickerPreviewHarness()
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
