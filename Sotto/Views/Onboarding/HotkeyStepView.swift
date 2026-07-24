import SwiftUI
import KeyboardShortcuts

struct HotkeyStepView: View {
    let onContinue: () -> Void

    @State private var shortcut: String = "⌥ SPACE"
    @State private var isUnbound: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SHORTCUT")
                .font(.microlabel(11))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundColor(Palette.inkSecondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 30)

            Text("Press the shortcut to dictate")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Palette.inkPrimary)

            Text("Sotto stays out of the way. Press this anywhere to start.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 12)

            shortcutPanel

            Text("You'll see a one-time reminder the first time. After that, Sotto is invisible.")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Spacer()

            HStack {
                Spacer()
                Button(action: onContinue) {
                    Text("Next")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(minWidth: 120)
                }
                .buttonStyle(OnboardingPhosphorButtonStyle(
                    horizontalPadding: 24,
                    verticalPadding: 11
                ))
                .accessibilityHint("Continue to model selection")
                Spacer()
            }
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear {
            if let bound = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) {
                shortcut = bound.description
                isUnbound = false
            } else {
                shortcut = "⌥ SPACE"
                isUnbound = true
            }
        }
    }

    private var shortcutPanel: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Text(shortcut)
                    .font(.mono(24, weight: .semibold))
                    .foregroundColor(Palette.inkPrimary)
                if isUnbound {
                    Button("Configure") {
                        NotificationCenter.default.post(
                            name: .navigateToDestination,
                            object: nil,
                            userInfo: ["destination": "Settings"]
                        )
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Palette.phosphor)
                }
            }
            .frame(width: 240, height: 88)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.mtRaise)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Palette.mtLine, lineWidth: 1)
            )
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dictation shortcut: \(shortcut)")
    }
}
