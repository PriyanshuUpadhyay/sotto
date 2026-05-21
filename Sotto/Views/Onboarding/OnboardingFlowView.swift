import SwiftUI

struct OnboardingFlowView: View {
    let onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            stepContent
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                HStack {
                    Spacer()
                    OnboardingSkipButton {
                        OnboardingState.shared.markSkipped()
                        onFinish()
                    }
                }
                Spacer()
            }
            .padding(16)
        }
        .frame(width: 480, height: 640)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            WelcomeStepView(onContinue: { step = step.next() })
        case .permissions:
            PermissionsStepView(onContinue: { step = step.next() })
        case .hotkey:
            HotkeyStepView(onFinish: {
                OnboardingState.shared.markCompleted()
                onFinish()
            })
        case .done:
            Color.clear
        }
    }
}

private struct OnboardingBackdrop: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if contrast == .increased {
                Color.black
            } else {
                Palette.onyxBg
                RadialGradient(
                    colors: [Palette.enhViolet.opacity(0.16), .clear],
                    center: UnitPoint(x: 0.2, y: 0.0),
                    startRadius: 0,
                    endRadius: 460
                )
                RadialGradient(
                    colors: [Palette.brandAcid.opacity(0.06), .clear],
                    center: UnitPoint(x: 1.0, y: 1.0),
                    startRadius: 0,
                    endRadius: 460
                )
            }
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingSkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("›")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(Palette.onyxMute)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip onboarding")
        .accessibilityHint("Skips setup and closes onboarding")
    }
}
