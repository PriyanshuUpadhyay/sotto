import SwiftUI

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String?

    var body: some View {
        GlassCard(cornerRadius: 2) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Palette.brandAcid.opacity(0.12))
                        Image(systemName: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Palette.brandAcid)
                    }
                    .frame(width: 30, height: 30)

                    Text(title.uppercased())
                        .font(.system(size: 10, design: .monospaced).weight(.bold))
                        .tracking(0.16 * 10)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Color.white.opacity(0.42))
                }

                Text(value)
                    .font(.system(size: 22, design: .monospaced).weight(.bold))
                    .foregroundStyle(Palette.brandAcid)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)\(detail.map { ", \($0)" } ?? "")")
    }
}
