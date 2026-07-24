import SwiftUI

/// Shared button style for SOLID Acid-Lime CTAs. Bakes DARK onyx text AND icons
/// (`Palette.surfaceBase`) onto a `Palette.brandAcid` (#D4FF3A) fill so the
/// white-text-on-lime contrast failure can NEVER be reintroduced at a call site.
///
/// Consume via `.buttonStyle(LimeFillButtonStyle())` (or `.buttonStyle(.limeFill)`
/// for the default pill). Do NOT set a per-site `.foregroundColor(...)` or
/// `.background(...brandAcid)` on the label — the style owns both the dark
/// foreground and the lime fill. Onyx system only: consumes `Palette` tokens.
struct LimeFillButtonStyle: ButtonStyle {
    /// Corner shape of the lime fill. `.capsule` for pill CTAs (model cards),
    /// `.rounded(radius)` for block CTAs (permissions row).
    enum FillShape {
        case capsule
        case rounded(CGFloat)
    }

    var shape: FillShape = .capsule
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 6
    /// Stretch to fill available width (block CTA). Pill CTAs stay intrinsic.
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // The contrast guarantee: dark onyx text AND icons on lime.
            .foregroundStyle(Palette.surfaceBase)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(fill)
            .overlay(border)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder private var fill: some View {
        switch shape {
        case .capsule:
            Capsule(style: .continuous)
                .fill(Palette.brandAcid)
                .shadow(color: Palette.brandAcid.opacity(0.2), radius: 2, x: 0, y: 1)
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Palette.brandAcid)
                .shadow(color: Palette.brandAcid.opacity(0.2), radius: 2, x: 0, y: 1)
        }
    }

    @ViewBuilder private var border: some View {
        switch shape {
        case .capsule:
            Capsule(style: .continuous)
                .stroke(Palette.hairline, lineWidth: 1)
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 1)
        }
    }
}

extension ButtonStyle where Self == LimeFillButtonStyle {
    /// Default pill (capsule) lime CTA: `.buttonStyle(.limeFill)`.
    static var limeFill: LimeFillButtonStyle { LimeFillButtonStyle() }
}
