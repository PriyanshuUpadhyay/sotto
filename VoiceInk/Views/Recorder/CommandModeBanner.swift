import SwiftUI

/// W12.B Command Mode banner. Single-line pill rendered above the recorder
/// chrome when `CommandModeService.isActive == true`. Honors plan §Migration
/// policy #10 — informational only, no captured-selection preview.
///
/// Reads `CommandModeService.shared` directly via `@ObservedObject` rather
/// than the environment — when this view is hosted inside the recorder
/// window managers' `AnyView`-wrapped trees, the `@EnvironmentObject`
/// lookup raced with SwiftUI's `DynamicContainerInfo.updateItems` and
/// crashed (`_assertionFailure` on missing env). Singleton + observed
/// object sidesteps the timing entirely.
struct CommandModeBanner: View {
    @ObservedObject var commandModeService: CommandModeService = .shared

    var body: some View {
        if commandModeService.isActive {
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Palette.accent.opacity(0.14))
            )
            .overlay(
                Capsule().stroke(Palette.accent.opacity(0.3), lineWidth: 0.5)
            )
            .padding(.top, 4)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var label: String {
        switch commandModeService.phase {
        case .rewriting:
            return "COMMAND MODE — REWRITING"
        case .pasting:
            return "COMMAND MODE — PASTING"
        default:
            return "COMMAND MODE"
        }
    }
}
