import SwiftUI

struct CommittedContent: View {
    @ObservedObject var ui: RecorderUIState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.commitGreen)

            MonoLabel(
                text: ui.lastPasteAppName.map { "PASTED → \($0.uppercased())" } ?? "PASTED",
                size: 10.5,
                color: Palette.commitGreen
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ui.lastPasteAppName.map { "Committed, pasted to \($0)" } ?? "Committed")
    }
}
