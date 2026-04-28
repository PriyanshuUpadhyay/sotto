import SwiftUI

// MARK: - LicenseView (P3.B)
//
// Compact license surface — used in legacy embeds + the SwiftUI preview. The
// production tab is `LicenseManagementView` (mounted from `ContentView` for
// `.license`); this view shares the same `LicenseHero` + `LicensePill`
// helpers below so both surfaces stay in lockstep.
//
// Layout per spec §3.6:
//   GlassCard {
//     hero (key.fill, warn → enhance gradient, 24pt glow)
//     "VoiceInk Pro" Display 24pt
//     LicensePill (state-driven: ACTIVE / TRIAL / EXPIRED)
//     mono license-key field (read-only when licensed)
//     [Activate] [Manage subscription]
//   }

struct LicenseView: View {
    @StateObject private var licenseViewModel = LicenseViewModel()

    var body: some View {
        ScrollView {
            GlassCard(cornerRadius: 22, padding: 32) {
                VStack(spacing: 24) {
                    LicenseHero()

                    VStack(spacing: 10) {
                        Text("VoiceInk Pro")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        LicensePill(state: licenseViewModel.licenseState)
                    }

                    LicenseKeyField(
                        text: $licenseViewModel.licenseKey,
                        readOnly: licenseViewModel.licenseState == .licensed
                    )

                    actionButtons

                    if let message = licenseViewModel.validationMessage {
                        Text(message)
                            .foregroundColor(licenseViewModel.validationSuccess ? Palette.success : Palette.recording)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 480)
            .padding(32)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            if case .licensed = licenseViewModel.licenseState {
                Button(role: .destructive) {
                    licenseViewModel.removeLicense()
                } label: {
                    Text("Remove License")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await licenseViewModel.validateLicense() }
                } label: {
                    HStack(spacing: 6) {
                        if licenseViewModel.isValidating {
                            ProgressView().controlSize(.small)
                        }
                        Text(licenseViewModel.isValidating ? "Activating…" : "Activate")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseViewModel.isValidating)
            }

            Button {
                if let url = URL(string: "https://polar.sh/beingpax/portal/request") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Manage subscription")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Shared subviews
//
// `LicenseHero`, `LicensePill`, `LicenseKeyField` are reused by
// `LicenseManagementView`. Kept module-internal here (rather than spinning a
// new file) because both consumers live in the same target.

/// SF Symbol hero per spec §3.6: `key.fill` 80pt, warn → enhance gradient,
/// 24pt glow shadow tinted with the warm gradient root.
struct LicenseHero: View {
    var body: some View {
        Image(systemName: "key.fill")
            .font(.system(size: 80, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Palette.warn, Palette.enhance],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: Palette.warn.opacity(0.45), radius: 24, x: 0, y: 0)
            .accessibilityHidden(true)
    }
}

/// Capsule pill — three mutually exclusive states matching `LicenseState`.
/// Color tokens come from `Palette` (no raw hex per reviewer focus).
struct LicensePill: View {
    let state: LicenseViewModel.LicenseState

    private var label: String {
        switch state {
        case .licensed:
            return "ACTIVE"
        case .trial(let days):
            return days == 1 ? "TRIAL · 1 DAY LEFT" : "TRIAL · \(days) DAYS LEFT"
        case .trialExpired:
            return "EXPIRED"
        }
    }

    private var tint: Color {
        switch state {
        case .licensed: return Palette.success
        case .trial: return Palette.transcribe
        case .trialExpired: return Palette.warn
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.0)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint))
            .accessibilityLabel("License status: \(label)")
    }
}

/// Mono license-key field — input when activating, read-only display when
/// `.licensed` (so the user can copy the key but not edit it accidentally).
struct LicenseKeyField: View {
    @Binding var text: String
    var readOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("License key")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            TextField("XXXX-XXXX-XXXX-XXXX", text: $text)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .disabled(readOnly)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
struct LicenseView_Previews: PreviewProvider {
    static var previews: some View {
        LicenseView()
    }
}
#endif
