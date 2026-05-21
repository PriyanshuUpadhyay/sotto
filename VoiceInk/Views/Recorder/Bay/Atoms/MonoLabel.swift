import SwiftUI

struct MonoLabel: View {
    let text: String
    var size: CGFloat = 11
    var tracking: CGFloat = 0.16
    var color: Color = Palette.brandAcid

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .tracking(tracking * size)
            .foregroundStyle(color)
            .accessibilityLabel(text)
    }
}
