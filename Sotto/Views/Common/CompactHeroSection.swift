import SwiftUI

struct CompactHeroSection: View {
    let icon: String
    let title: String
    let description: String
    var maxDescriptionWidth: CGFloat? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Palette.brandAcid)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text(title)
                    .font(.ui(22, weight: .bold))
                Text(description)
                    .font(.ui(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: maxDescriptionWidth)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}
