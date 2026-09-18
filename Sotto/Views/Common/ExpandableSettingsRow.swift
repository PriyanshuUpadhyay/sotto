import SwiftUI

// MARK: - Expandable Settings Row

/// A toggle whose options fold out below it. Native `DisclosureGroup` owns the
/// expand/collapse click, keyboard and VoiceOver handling; the options only
/// show while the toggle is on, and turning it on opens them.
struct ExpandableSettingsRow<Content: View>: View {
    @Binding var isExpanded: Bool
    @Binding var isEnabled: Bool
    let label: String
    var infoMessage: String? = nil
    var infoURL: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { isEnabled && isExpanded },
            set: { isExpanded = $0 }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Toggle(isOn: $isEnabled) {
                HStack(spacing: 4) {
                    Text(label)
                    if let message = infoMessage {
                        if let url = infoURL {
                            InfoTip(message, learnMoreURL: url)
                        } else {
                            InfoTip(message)
                        }
                    }
                }
            }
        }
        .onChange(of: isEnabled) { _, newValue in
            withAnimation(Animation.haloPhaseCrossfade) {
                isExpanded = newValue
            }
        }
    }
}
