import SwiftUI

struct HelpAndResourcesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Help & Resources")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 10) {
                resourceLink(
                    icon: "sparkles",
                    title: "Recommended Models",
                    url: "https://tryvoiceink.com/recommended-models"
                )

                resourceLink(
                    icon: "video.fill",
                    title: "YouTube Videos & Guides",
                    url: "https://www.youtube.com/@tryvoiceink/videos"
                )

                resourceLink(
                    icon: "book.fill",
                    title: "Documentation",
                    url: "https://tryvoiceink.com/docs"
                )

                resourceLink(
                    icon: "exclamationmark.bubble.fill",
                    title: "Feedback or Issues?",
                    action: {
                        EmailSupport.openSupportEmail()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
    }

    private func resourceLink(icon: String, title: String, url: String? = nil, action: (() -> Void)? = nil) -> some View {
        Button(action: {
            if let action = action {
                action()
            } else if let urlString = url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Palette.brandAcid)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13))
                    .fontWeight(.semibold)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .foregroundColor(.secondary)
            }
            .glassChip(cornerRadius: 10)
        }
        .buttonStyle(.plain)
    }
}
