import SwiftUI
import AppKit

// MARK: - AdaptiveGlassBackground (W8 — adaptive glass app-wide)
//
// View modifier that paints an adaptive-glass background on a full-bleed
// surface (pane root / sliding-panel root / popover host). Mirrors the
// recorder's HaloMaterial vocabulary (spec §2.3) — onyx-vs-light variant
// driven by `GlassAppearanceDetector.shared.current`. Diverges from
// HaloMaterial only in:
//   • shape: full-bleed Rectangle, not a clipped RoundedRectangle.
//   • inner stroke / sheen / drop-shadow: omitted — too noisy at pane scale.
//   • intensity: a 2-step ramp (.pane / .panel) for layered surfaces
//     (panel sits over pane → slightly higher fill alpha to read as
//     stepped-up).
//
// Reuses `VisualEffectBlur` from `Recorder/HaloMaterial.swift` to avoid
// duplicating the NSViewRepresentable wrapper.
//
// Accessibility branches once at the top of the body:
//   • Reduce-Transparency on  → opaque Color(NSColor.controlBackgroundColor)
//                                (system-adaptive, matches preference)
//   • Increase-Contrast on    → opaque Color(NSColor.windowBackgroundColor)
//                                (matches HaloMaterial.AdaptiveGlass.contrastedFill
//                                 contract, spec §6.4)
//   • Else (default)          → VisualEffectBlur(.fullScreenUI / .behindWindow)
//                                + tint overlay keyed to detector.current.
//
// Window-transparency contract:
//   The host NSWindow MUST have `isOpaque = false` + `backgroundColor = .clear`
//   for `.behindWindow` blending to reveal wallpaper. WindowManager.configureWindow
//   sets these flags (W8 plan Task 2). Without them, the modifier degrades to
//   a translucent overlay over the window's own background — still readable,
//   but the wallpaper-luminance adaptation reads as system-appearance only.
//
// Spec refs:
//   docs/superpowers/specs/2026-04-28-aesthetic-redesign.md §1, §2.3, §6.1, §6.4
//   docs/superpowers/plans/W8-adaptive-glass-app-wide.md

enum AdaptiveGlassIntensity {
    /// Detail-pane root — the gap area behind cards. Lower fill alpha.
    case pane
    /// Sliding-panel chrome — the stepped-up surface above a pane.
    /// Higher fill alpha so the panel reads as a distinct layer.
    case panel
}

struct AdaptiveGlassBackground: ViewModifier {
    var intensity: AdaptiveGlassIntensity = .pane

    @ObservedObject private var detector = GlassAppearanceDetector.shared

    func body(content: Content) -> some View {
        content.background(backdrop)
    }

    @ViewBuilder
    private var backdrop: some View {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        if reduceTransparency {
            Color(NSColor.controlBackgroundColor)
        } else if highContrast {
            Color(NSColor.windowBackgroundColor)
        } else {
            ZStack {
                VisualEffectBlur(
                    material: .fullScreenUI,
                    blendingMode: .behindWindow,
                    appearanceName: detector.current == .light ? .aqua : .darkAqua
                )
                tint
            }
        }
    }

    private var tint: Color {
        switch (detector.current, intensity) {
        case (.onyx,  .pane):  return Color.black.opacity(0.42)
        case (.onyx,  .panel): return Color.black.opacity(0.52)
        case (.light, .pane):  return Color.white.opacity(0.18)
        case (.light, .panel): return Color.white.opacity(0.26)
        }
    }
}

extension View {
    /// Paints an adaptive-glass backdrop suitable for a detail-pane root or
    /// a sliding-panel chrome. Branches on Reduce-Transparency / High-Contrast
    /// per spec §6.4. See `AdaptiveGlassBackground` for the contract.
    func adaptiveGlassBackground(intensity: AdaptiveGlassIntensity = .pane) -> some View {
        modifier(AdaptiveGlassBackground(intensity: intensity))
    }
}

// MARK: - Previews

#if DEBUG
private struct AdaptiveGlassBackgroundPreviewBody: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Detail pane root").font(.system(size: 13, weight: .semibold))
            GlassCard(cornerRadius: 14, padding: 16) {
                Text("Card on glass").frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 320)
        }
        .padding(40)
    }
}

#Preview("Onyx pane") {
    AdaptiveGlassBackgroundPreviewBody()
        .adaptiveGlassBackground()
        .frame(width: 480, height: 360)
}

#Preview("Onyx panel") {
    AdaptiveGlassBackgroundPreviewBody()
        .adaptiveGlassBackground(intensity: .panel)
        .frame(width: 480, height: 360)
}
#endif
