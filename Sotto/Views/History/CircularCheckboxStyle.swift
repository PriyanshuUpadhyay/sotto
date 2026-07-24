import SwiftUI

/// Circular checkbox toggle style used by the history selection UI.
/// Extracted from the (deleted) TranscriptionListItem island — still consumed
/// by the live InlineHistoryView selection checkboxes.
struct CircularCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(configuration.isOn ? Brand.tint : .secondary)
                .font(.system(size: 18))
        }
        .buttonStyle(.plain)
    }
}
