import SwiftUI

struct WelcomeStepView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            wordmark
                .opacity(visible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: visible)

            Text("› sotto voce · under your voice")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(Palette.onyxMute)
                .opacity(visible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24).delay(0.12), value: visible)

            Spacer()
            Spacer()

            Button(action: onContinue) {
                Text("▸ Get started")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(Palette.brandAcid)
                    .frame(width: 220, height: 44)
                    .background(
                        TacticalGlass(
                            shape: RoundedRectangle(cornerRadius: SottoGeometry.cornerRadiusNotch, style: .continuous),
                            phase: .armed
                        )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Begin Sotto setup")

            Spacer().frame(height: 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { visible = true }
    }

    private var wordmark: some View {
        (Text("Sotto").foregroundColor(Palette.onyxFg)
            + Text(".").foregroundColor(Palette.brandAcid))
            .font(.system(size: 56, weight: .bold, design: .monospaced))
            .tracking(1.0)
            .accessibilityLabel("Sotto")
            .accessibilityAddTraits(.isHeader)
    }
}
