import SwiftUI

struct AppNotificationView: View {
    let title: String
    let type: NotificationType
    let duration: TimeInterval
    let onClose: () -> Void
    let onTap: (() -> Void)?
    var actionButton: (label: String, action: () -> Void)? = nil

    @State private var progress: Double = 1.0
    @State private var timer: Timer?
    @Environment(\.colorSchemeContrast) private var contrast

    private static let cornerRadius: CGFloat = 12

    enum NotificationType {
        case error
        case warning
        case info
        case success

        var iconName: String {
            switch self {
            case .error: return "xmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }

        /// Matte state-grammar accent (spec §4): fail→amber, info→phosphor,
        /// commit→green. The glyph carries the non-color cue; hue is redundant.
        var accent: Color {
            switch self {
            case .error, .warning: return Palette.stateFail
            case .info:            return Palette.phosphor
            case .success:         return Palette.stateCommit
            }
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return ZStack {
            HStack(alignment: .center, spacing: 12) {
                // Type icon
                Image(systemName: type.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(type.accent)
                    .frame(width: 20, height: 20)

                // Single message text
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.inkPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                if let actionButton {
                    Button(action: {
                        actionButton.action()
                        onClose()
                    }) {
                        Text(actionButton.label)
                            .font(.mono(11, weight: .semibold))
                            .foregroundColor(type.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(type.accent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.control))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Palette.inkSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 220, maxWidth: 750, minHeight: 44)
        .background(shape.fill(Palette.mtRaise))
        .overlay(
            shape.strokeBorder(A11y.borderColor(increaseContrast: contrast == .increased), lineWidth: 1)
        )
        .overlay(
            VStack {
                Spacer()
                GeometryReader { geometry in
                    Rectangle()
                        .fill(type.accent.opacity(0.8))
                        .frame(width: geometry.size.width * max(0, progress), height: 2)
                        .animation(.linear(duration: 0.1), value: progress)
                }
                .frame(height: 2)
            }
            .clipShape(shape)
        )
        .onAppear {
            startProgressTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onTapGesture {
            if let onTap = onTap {
                onTap()
                onClose()
            }
        }
    }
    
    private func startProgressTimer() {
        let updateInterval: TimeInterval = 0.1
        let totalSteps = duration / updateInterval
        let stepDecrement = 1.0 / totalSteps
        
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            if progress > 0 {
                progress = max(0, progress - stepDecrement)
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
    }
}

