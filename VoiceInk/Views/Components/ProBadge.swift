import SwiftUI

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Palette.onyxFg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Palette.accent.opacity(0.8))
            )
    }
}

#Preview {
    ProBadge()
} 