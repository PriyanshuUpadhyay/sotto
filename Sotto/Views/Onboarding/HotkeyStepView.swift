import SwiftUI
import KeyboardShortcuts

struct HotkeyStepView: View {
    let onFinish: () -> Void

    @State private var shortcut: String = "⌥ SPACE"
    @State private var isUnbound: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("› SHORTCUT")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.76)
                .foregroundColor(Palette.brandAcid)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 30)

            Text("Press the shortcut to dictate")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(Palette.onyxFg)

            Text("Sotto stays out of the way. Press this anywhere to start.")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(Palette.onyxMute)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 12)

            shortcutPanel

            Text("You'll see a one-time reminder the first time. After that, Sotto is invisible.")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(Palette.onyxMute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Spacer()

            HStack {
                Spacer()
                Button(action: onFinish) {
                    Text("▸ Finish")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundColor(Palette.brandAcid)
                        .frame(width: 160, height: 44)
                        .background(
                            TacticalGlass(
                                shape: RoundedRectangle(cornerRadius: SottoGeometry.cornerRadiusNotch, style: .continuous),
                                phase: .armed
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Finish setup and close onboarding")
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
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(Palette.onyxFg)
                if isUnbound {
                    Button("Configure ›") {
                        NotificationCenter.default.post(
                            name: .navigateToDestination,
                            object: nil,
                            userInfo: ["destination": "Settings"]
                        )
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Palette.brandAcid)
                }
            }
            .frame(width: 240, height: 88)
            .background(
                TacticalGlass(
                    shape: RoundedRectangle(cornerRadius: SottoGeometry.cornerRadiusNotch, style: .continuous),
                    phase: .armed
                )
            )
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dictation shortcut: \(shortcut)")
    }
}
