import SwiftUI

/// A reusable info tip component that displays helpful information in a popover
struct InfoTip: View {
    // Content configuration
    var message: String
    var learnMoreLink: URL?

    // Appearance customization
    var iconName: String = "info.circle.fill"
    var iconSize: Image.Scale = .medium
    var iconColor: Color = .primary
    var width: CGFloat = 280

    // State
    @State private var isShowingTip: Bool = false

    var body: some View {
        // A Button, not a tappable Image: as an Image it took no key focus and
        // announced no label, so the explanation was mouse-only.
        Button {
            isShowingTip.toggle()
        } label: {
            Image(systemName: iconName)
                .imageScale(iconSize)
                .foregroundColor(iconColor)
                .fontWeight(.semibold)
                .padding(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More information")
        // Anchored to its source view, which is the origin-aware behavior.
        .popover(isPresented: $isShowingTip) {
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.callout)
                    .foregroundColor(.secondary)

                if let url = learnMoreLink {
                    Link("Learn more", destination: url)
                        .font(.callout)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: .leading)
            .padding(14)
        }
    }
}

// MARK: - Convenience initializers

extension InfoTip {
    /// Creates an InfoTip with just a message
    init(_ message: String) {
        self.message = message
        self.learnMoreLink = nil
    }

    /// Creates an InfoTip with a learn more link
    init(_ message: String, learnMoreURL: String) {
        self.message = message
        self.learnMoreLink = URL(string: learnMoreURL)
    }
}
