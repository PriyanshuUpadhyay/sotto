import SwiftUI

// MARK: - SettingsCard
//
// Wraps a single Settings section in a glass island per spec §3.3.
//
// Composition:
//   GlassCard {
//     SettingsSectionHeader  ← reuses v1 baseline header
//     Divider (faint)
//     content stack (typically a column of `SettingsRow`s)
//   }
//
// Reuses the existing `SettingsSectionHeader` (icon tile + title + subtitle +
// optional status pill) rather than re-rendering its semantics — same
// vocabulary, same a11y read order.
// Adaptive material (appearance + opacity) is inherited from `GlassCard`.
// The hover signal hook is retained but no longer translates the card.
//
// Form-chrome mitigation (per plan §P2.D risks): consumer hosts these in a
// `ScrollView { LazyVStack }`, NOT a `Form`. Putting `SettingsCard` inside a
// `Form { Section { } }` double-layers the section background under the glass
// material. `SettingsView.swift` strips Form entirely for this reason.

struct SettingsCard<Content: View>: View {
    let iconSystemName: String
    let iconTint: Color
    let title: String
    var subtitle: String? = nil
    var statusText: String? = nil
    var statusTone: SettingsSectionHeader.StatusTone = .neutral
    var appearance: GlassAppearance? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(
                icon: iconSystemName,
                title: title,
                subtitle: subtitle,
                accent: iconTint,
                statusText: statusText,
                statusTone: statusTone
            )

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(shape.fill(Theme.panel))
        .overlay(shape.strokeBorder(A11y.borderColor(increaseContrast: contrast == .increased), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - OnyxSurfaceCard
//
// Drop-in nested-card surface for Settings / AI-Model / Vocabulary call sites
// that nest a card INSIDE a `SettingsCard` (which is `Theme.elevated`). Steps to
// an appearance-adaptive grouped fill + hairline `Theme.separator`, continuous
// radius — never translucent glass. Same `(cornerRadius:padding:)` signature as
// `GlassCard` so call sites swap by name only. Callers that draw their own
// selection stroke (e.g. model cards' accent-when-current overlay) keep it — it
// renders over the edge.

struct OnyxSurfaceCard<Content: View>: View {
    var cornerRadius: CGFloat = Radius.card
    var padding: CGFloat = 14
    @ViewBuilder let content: () -> Content

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content()
            .padding(padding)
            .background(shape.fill(Theme.selectedRow))
            .overlay(shape.strokeBorder(A11y.borderColor(increaseContrast: contrast == .increased), lineWidth: 1))
    }
}

// MARK: - Previews

#if DEBUG
private struct SettingsCardPreviewBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(
                iconSystemName: "command",
                iconTint: Brand.tint,
                title: "Shortcuts",
                subtitle: "Trigger recording from anywhere.",
                statusText: "1 active",
                appearance: nil
            ) {
                Text("[Shortcut row 1]")
                    .foregroundColor(.secondary)
                Text("[Shortcut row 2]")
                    .foregroundColor(.secondary)
            }
            .frame(width: 480)

            SettingsCard(
                iconSystemName: "lock.fill",
                iconTint: Palette.success,
                title: "Privacy",
                subtitle: "Local-first by default. Audio stays on this Mac.",
                appearance: nil
            ) {
                Text("[Cleanup row]")
                    .foregroundColor(.secondary)
            }
            .frame(width: 480)
        }
    }
}

#Preview("Onyx") {
    ScrollView {
        SettingsCardPreviewBody()
            .padding(40)
    }
    .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Light") {
    ScrollView {
        SettingsCardPreviewBody()
            .padding(40)
    }
    .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
