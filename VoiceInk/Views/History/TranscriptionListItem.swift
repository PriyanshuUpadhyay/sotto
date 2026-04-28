import SwiftUI

// MARK: - TranscriptionListItem (P3.A)
//
// History list row. The container view sets the glass surface; the row
// keeps its existing typography + selection ring. Background uses an
// alternating-luminance fill so adjacent rows separate visually without
// drawing dividers.
//
// Hover-lift: 2pt translate-y on cursor enter, 0.18s ease. Calmer list
// rhythm than the now-zero `GlassCard` primitive — kept locally per
// design intent. Reduce Motion short-circuits the spring.

struct TranscriptionListItem: View {
    let transcription: Transcription
    let isSelected: Bool
    let isChecked: Bool
    let rowIndex: Int
    let onSelect: () -> Void
    let onToggleCheck: () -> Void

    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { isChecked },
                set: { _ in onToggleCheck() }
            ))
            .toggleStyle(CircularCheckboxStyle())
            .labelsHidden()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(transcription.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    if transcription.duration > 0 {
                        Text(transcription.duration.formatTiming())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.06 * 10)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule().fill(Palette.neutral.opacity(0.14))
                            )
                            .overlay(
                                Capsule().stroke(Palette.neutral.opacity(0.28), lineWidth: 0.5)
                            )
                            .foregroundColor(.secondary)
                    }
                }

                Text(transcription.enhancedText ?? transcription.text)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(2)
                    .foregroundColor(.primary)
            }
        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
        }
        .overlay {
            // Selection ring matches the halo's accent — keeps visual
            // language consistent between recorder and history list.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Palette.accent.opacity(0.45) : Color.clear,
                        lineWidth: 1)
        }
        .offset(y: isHovering && !isSelected ? -2 : 0)
        .animation(motion.reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovering)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }

    /// Alternating-luminance glass tint: even rows lift slightly off the
    /// container so adjacent rows separate without dividers. Selection wins
    /// over alternation so the picked row reads as the focal element.
    private var rowFill: Color {
        if isSelected {
            return Palette.accent.opacity(0.10)
        }
        return rowIndex.isMultiple(of: 2)
            ? Color.primary.opacity(0.045)
            : Color.primary.opacity(0.015)
    }
}

struct CircularCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(configuration.isOn ? Color(NSColor.controlAccentColor) : .secondary)
                .font(.system(size: 18))
        }
        .buttonStyle(.plain)
    }
}
