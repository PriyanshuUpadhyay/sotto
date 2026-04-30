import SwiftUI

struct CopyIconButton: View {
    let textToCopy: String
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(copied ? Palette.success : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color(red: 0.078, green: 0.078, blue: 0.110).opacity(0.55))
                        .background(Circle().fill(.ultraThinMaterial))
                )
                .overlay(Circle().stroke(Palette.hairline, lineWidth: 1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
    }

    private func copy() {
        let _ = ClipboardManager.copyToClipboard(textToCopy)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}
