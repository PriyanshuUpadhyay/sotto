import SwiftUI

// MARK: - LicenseManagementView (P3.B)
//
// Production license tab — mounted from `ContentView` for the `.license`
// sidebar route. Same hero/pill vocabulary as `LicenseView` (helpers live in
// LicenseView.swift) plus a secondary glass strip for resource links
// (Changelog / Discord / Support / Docs / Tip Jar) and a buy CTA when the
// user is not yet licensed.
//
// Wiring preserved from v1: validateLicense, removeLicense, buy URL, license
// portal URL, EmailSupport.openSupportEmail, all resource links.

struct LicenseManagementView: View {
    @StateObject private var licenseViewModel = LicenseViewModel()

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroCard
                resourcesCard
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(32)
        }
    }

    // MARK: - Hero card (glass)

    private var heroCard: some View {
        GlassCard(cornerRadius: 22, padding: 32) {
            VStack(spacing: 24) {
                LicenseHero()

                VStack(spacing: 10) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("VoiceInk Pro")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("v\(appVersion)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.secondary)
                    }

                    LicensePill(state: licenseViewModel.licenseState)
                }

                LicenseKeyField(
                    text: $licenseViewModel.licenseKey,
                    readOnly: licenseViewModel.licenseState == .licensed
                )

                actionButtons

                if let message = licenseViewModel.validationMessage {
                    Text(message)
                        .foregroundColor(licenseViewModel.validationSuccess ? Palette.success : Palette.accent)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }

                if case .licensed = licenseViewModel.licenseState, licenseViewModel.activationsLimit > 0 {
                    Text("This license can be activated on up to \(licenseViewModel.activationsLimit) devices.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Action row
    //
    // Licensed → [Deactivate] [Manage subscription]
    // Otherwise → [Buy License] [Activate] [Manage subscription]

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            if case .licensed = licenseViewModel.licenseState {
                Button(role: .destructive) {
                    licenseViewModel.removeLicense()
                } label: {
                    Label("Deactivate", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    if let url = URL(string: "https://tryvoiceink.com/buy") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Buy License", systemImage: "cart.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

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
                .buttonStyle(.bordered)
                .disabled(licenseViewModel.isValidating)
            }

            Button {
                if let url = URL(string: "https://polar.sh/beingpax/portal/request") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Manage", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Resources card (glass strip)

    private var resourcesCard: some View {
        GlassCard(cornerRadius: 16, padding: 20) {
            HStack(spacing: 24) {
                resourceLink(
                    icon: "list.bullet.clipboard.fill",
                    title: "Changelog",
                    tint: Palette.accent,
                    url: "https://github.com/Beingpax/VoiceInk/releases"
                )
                resourceLink(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Discord",
                    tint: Palette.accent,
                    url: "https://discord.gg/xryDy57nYD"
                )
                Button {
                    EmailSupport.openSupportEmail()
                } label: {
                    resourceItemLabel(icon: "envelope.fill", title: "Support", tint: Palette.warn)
                }
                .buttonStyle(.plain)
                resourceLink(
                    icon: "book.fill",
                    title: "Docs",
                    tint: Palette.success,
                    url: "https://tryvoiceink.com/docs"
                )
                resourceLink(
                    icon: "heart.fill",
                    title: "Tip Jar",
                    tint: Palette.accent,
                    url: "https://buymeacoffee.com/beingpax"
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func resourceLink(icon: String, title: String, tint: Color, url: String) -> some View {
        Button {
            if let u = URL(string: url) {
                NSWorkspace.shared.open(u)
            }
        } label: {
            resourceItemLabel(icon: icon, title: title, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func resourceItemLabel(icon: String, title: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview {
    LicenseManagementView()
        .frame(width: 720, height: 800)
}
#endif
