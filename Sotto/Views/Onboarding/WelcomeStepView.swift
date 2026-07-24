import SwiftUI

struct WelcomeStepView: View {
    let onContinue: () -> Void
    var onSkipToEssentials: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            wordmark
                .opacity(visible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: visible)

            Text("› sotto voce · under your voice")
                .font(.mono(13))
                .tracking(0.5)
                .foregroundColor(Palette.inkSecondary)
                .opacity(visible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24).delay(0.12), value: visible)

            Spacer()
            Spacer()

            Button(action: onContinue) {
                Text("Get started")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(minWidth: 180)
            }
            .buttonStyle(OnboardingPhosphorButtonStyle(
                horizontalPadding: 24,
                verticalPadding: 13
            ))
            .accessibilityHint("Begin Sotto setup")

            if let onSkipToEssentials {
                Button(action: onSkipToEssentials) {
                    Text("Skip to essentials")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Palette.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Set up only the microphone, shortcut, and model")
            }

            Spacer().frame(height: 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { visible = true }
    }

    private var wordmark: some View {
        (Text("Sotto").foregroundColor(Palette.inkPrimary)
            + Text(".").foregroundColor(Palette.phosphor))
            .font(.wordmark(56))
            .tracking(1.0)
            .accessibilityLabel("Sotto")
            .accessibilityAddTraits(.isHeader)
    }
}
