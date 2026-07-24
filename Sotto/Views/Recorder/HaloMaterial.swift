import SwiftUI
import AppKit

// MARK: - HaloPhase
//
// View-side phase that drives material/halo color and motion. Maps from engine
// `RecordingState` + partial transcript presence. Defined here so material,
// recorder view, and pulse ribbon can all read it without circular imports.

enum HaloPhase: Equatable {
    case hidden
    case armed       // visible, no audio yet (idle-armed) — currently unused at v1, reserved
    case recording
    case transcribing
    case enhancing
    case liveText    // recording + partial transcript visible
    case failed      // post-action red flash (engine emits this for ~1.2s on error)
    case done        // post-action green confirmation (brief)
}

// Conceptual 7-state mapping (Sotto spec §4):
//   idle        ↔ .hidden          (orderOut + subtree unmount — see NotchWindowManager.hide)
//   arming      ↔ .armed           (breathing lime, peak alpha 0.45)
//   recording   ↔ .recording / .liveText
//   transcribing↔ .transcribing
//   enhancing   ↔ .enhancing
//   committed   ↔ .done             (green confirm halo, 1.5s dwell at view layer)
//   fail        ↔ .failed           (red error blink, persists until dismissed)
extension HaloPhase {
    var glowColor: Color {
        switch self {
        case .hidden:                   return .clear
        case .armed:                    return Palette.brandAcid       // breathing lime (arming)
        case .recording, .liveText:     return Palette.recRed           // red dot + halo
        case .transcribing:             return Palette.transCyan        // cyan sweep
        case .enhancing:                return Palette.enhViolet        // violet halo breath
        case .failed:                   return Palette.recRed           // red error blink
        case .done:                     return Palette.commitGreen      // green confirm halo
        }
    }

    var glowAlpha: Double {
        switch self {
        case .hidden:                   return 0.0
        // Peak alpha for the arming breathe (0.4–0.9 envelope at view layer);
        // breathePulse modulates around this peak.
        case .armed:                    return 0.45
        case .recording, .liveText:     return Palette.HaloIntensity.soft.alpha
        case .transcribing:             return Palette.HaloIntensity.medium.alpha
        case .enhancing:                return Palette.HaloIntensity.strong.alpha
        case .failed:                   return Palette.HaloIntensity.strong.alpha
        case .done:                     return Palette.HaloIntensity.medium.alpha
        }
    }
}

// MARK: - VisualEffectBlur

/// Bridges `NSVisualEffectView` into SwiftUI. Behind-window blur of the desktop wallpaper.
/// Material spike notes: panel must have `isOpaque = false`, `backgroundColor = .clear`, and the
/// hosting controller's view must clear its layer background — both already true for the
/// recorder panels. `.statusBar+3` window level affects only z-order, not compositing.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    /// `.darkAqua` for onyx glass, `.aqua` for light glass.
    var appearanceName: NSAppearance.Name = .darkAqua

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = false
        view.appearance = NSAppearance(named: appearanceName)
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.appearance = NSAppearance(named: appearanceName)
    }
}

// MARK: - HaloMaterial
//
// The recorder HUD's bespoke silhouette on a NATIVE Liquid Glass substrate
// (Sotto Apple-native pivot, P5 — council 2026-06-03, option ii). The HUD is
// the ONE surface that keeps Sotto's branded onyx/lime identity; distinctiveness
// now comes from the notch geometry + colored state choreography + lime, NOT a
// hand-rolled opaque dark rectangle.
//
// Substrate (replaces the old NSVisualEffectView-blur + black@0.60 slab):
//   • macOS 26 (Tahoe): SwiftUI `.glassEffect(.regular, in: shape)` — system
//     Liquid Glass that reads legibly over LIGHT and dark wallpapers alike.
//   • Pre-26 fallback: `shape.fill(.regularMaterial)` system vibrancy.
//   • Reduce Transparency / Increase Contrast: an OPAQUE adaptive fill
//     (`AdaptiveGlass.contrastedFill`) so the HUD stays legible.
//
// Layers composed over the substrate (both variants):
//   • Brand tint scrim — a THIN onyx/light wash (not the old slab) for identity.
//   • Inner top gloss — 1.5pt linear gradient (decorative; off under HC).
//   • Inner stroke — 0.5pt silhouette edge (1pt solid accent under HC).
//   • Bottom inner stroke — depth cue (off under HC).
//   • Inner sheen (enhancing only) — radial violet above the strokes.
//   • State-keyed outer halo — 24px blur, color from HaloPhase (off under HC).
//   • Drop shadow — variant-specific blur/offset/alpha.

struct HaloMaterial<S: Shape>: View {
    let shape: S
    let phase: HaloPhase
    /// Drives the `breathe` motion for the enhancing state (0…1, easing externally).
    var breathePulse: Double = 0
    /// `true` while enhancing — intensifies the inner sheen.
    var showInnerSheen: Bool = false
    /// Light vs. onyx glass. Defaults to `.onyx` for source-compat with v1 callers.
    var appearance: GlassAppearance = .onyx

    var body: some View {
        let glow = phase.glowColor
        let glowA = phase.glowAlpha + (showInnerSheen ? breathePulse * 0.06 : 0)
        // Read once per render — both are system-wide a11y flags that change via
        // system notifications, so per-render sampling is fine.
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        // Either flag demands an opaque, legible surface — collapse the live
        // glass to the adaptive opaque fill.
        let opaqueSubstrate = highContrast || reduceTransparency

        ZStack {
            // 1. Substrate — native Liquid Glass (macOS 26) / system vibrancy,
            //    replacing the hand-rolled behind-window blur + opaque-black slab
            //    (council 2026-06-03, option ii). Collapses to an opaque adaptive
            //    fill under Reduce Transparency / Increase Contrast.
            substrate(opaque: opaqueSubstrate)

            // 2. Brand tint scrim — a THIN onyx/light wash over the live glass so
            //    the surface keeps its identity without the old dark rectangle.
            //    Suppressed when the substrate is already opaque.
            if !opaqueSubstrate {
                shape.fill(tintScrim)
            }

            // 3. Inner top gloss — decorative; suppressed under High Contrast
            //    to keep the surface uniformly opaque.
            if !highContrast {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: topGlossColors,
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 1.5)
                    Spacer(minLength: 0)
                }
            }

            // 5. Bottom inner stroke — depth cue; suppressed under High Contrast
            //    (the 1pt solid inner stroke carries the silhouette alone).
            if !highContrast {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(bottomStrokeColor)
                        .frame(height: 0.5)
                }
            }
        }
        .clipShape(shape)
        // 4. Inner stroke — defines silhouette. Applied above the clip so the
        //    half-outside pixels of the stroke aren't cropped. Under High Contrast
        //    becomes a 1pt solid in the state's accent color (spec §6.4).
        .overlay(
            shape.stroke(
                highContrast ? AdaptiveGlass.contrastedStroke(for: phase) : innerStrokeColor,
                lineWidth: highContrast ? 1 : 0.5
            )
        )
        // 6. Inner sheen (enhancing only) — radial soft violet sweeping center.
        //    Per spec §2.3 #6 the sheen renders ABOVE both inner strokes (top + bottom),
        //    so it sits as an overlay after the inner-stroke overlay. Clipped to
        //    `shape` so it doesn't bleed past the silhouette. Suppressed under
        //    High Contrast (decorative motion tied to the breathe pulse).
        .overlay(
            Group {
                if showInnerSheen && !highContrast {
                    RadialGradient(
                        colors: [glow.opacity(0.22 + breathePulse * 0.08), .clear],
                        center: .center, startRadius: 0, endRadius: 90
                    )
                    .blendMode(.plusLighter)
                    .opacity(0.55)
                }
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        )
        // 7. Halo glow — outside the clip, color-keyed. Suppressed under High
        //    Contrast per `AdaptiveGlass.contrastedHaloDisabled` (spec §6.4
        //    "halo glows hidden"). The 1pt solid inner stroke takes over as
        //    the state indicator.
        .shadow(
            color: (highContrast && AdaptiveGlass.contrastedHaloDisabled)
                ? Color.clear
                : glow.opacity(glowA),
            radius: 24,
            x: 0,
            y: 4
        )
        // 8. Soft drop shadow — variant-specific blur/offset/alpha. Preserved
        //    under High Contrast (depth cue independent of state).
        .shadow(
            color: dropShadowColor,
            radius: dropShadowRadius,
            x: 0,
            y: dropShadowOffsetY
        )
    }

    // MARK: - Substrate

    /// Native material substrate. macOS 26 Liquid Glass when available, system
    /// vibrancy otherwise; an opaque adaptive fill under Reduce Transparency /
    /// Increase Contrast.
    @ViewBuilder
    private func substrate(opaque: Bool) -> some View {
        if opaque {
            // `windowBackgroundColor` tracks Light/Dark + the Increase-Contrast
            // pass, so the opaque fallback stays appearance-correct.
            AdaptiveGlass.contrastedFill(for: phase)
        } else if #available(macOS 26.0, *) {
            // Tahoe Liquid Glass — reads legibly over LIGHT and dark wallpapers.
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            // Pre-26 system vibrancy. `Material` is appearance-adaptive and
            // already honors Reduce Transparency on its own.
            shape.fill(.regularMaterial)
        }
    }

    // MARK: - Variant tokens

    /// Thin identity wash over the live glass. Replaces the old opaque black@0.60
    /// slab — distinctiveness now comes from notch geometry + state color + lime,
    /// not a dark rectangle.
    private var tintScrim: Color {
        switch appearance {
        case .onyx:  return Color.black.opacity(0.18)
        case .light: return Color.white.opacity(0.10)
        }
    }

    private var topGlossColors: [Color] {
        switch appearance {
        case .onyx:
            return [Color.white.opacity(0.30), Color.white.opacity(0.0)]
        case .light:
            return [Color.white.opacity(0.70), Color.white.opacity(0.18)]
        }
    }

    private var innerStrokeColor: Color {
        switch appearance {
        // Crisp grounded edge — consume the shared `Palette.hairline` token
        // (white@0.16) so every chip carries the same silhouette outline and
        // reads as a solid object, not a smudge.
        case .onyx:  return Palette.hairline
        case .light: return Color.white.opacity(0.55)
        }
    }

    private var bottomStrokeColor: Color {
        switch appearance {
        case .onyx:  return Color.white.opacity(0.05)
        case .light: return Color.white.opacity(0.18)
        }
    }

    private var dropShadowColor: Color {
        switch appearance {
        case .onyx:  return Color.black.opacity(0.30)
        case .light: return Color.black.opacity(0.18)
        }
    }

    private var dropShadowRadius: CGFloat {
        switch appearance {
        case .onyx:  return 10
        case .light: return 24
        }
    }

    private var dropShadowOffsetY: CGFloat {
        switch appearance {
        case .onyx:  return 4
        case .light: return 8
        }
    }
}

// MARK: - AdaptiveGlass — High-Contrast constants
//
// Centralized High-Contrast tokens read by every glass surface when
// `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` is true.
// Spec §6.4: "Glass tints become opaque; inner strokes become 1pt solid;
// halo glows hidden (replaced by 2pt solid border in state color)."
//
// Plan §P1.A resolves the open numeric question by exposing this namespace
// so downstream packets (P2.A glass primitives, P3.A–G surfaces) consume
// uniform values instead of re-deriving High-Contrast logic per-surface.
//
// Surfaces should branch ONCE on `accessibilityDisplayShouldIncreaseContrast`
// and use these tokens — do not invent new High-Contrast values.

enum AdaptiveGlass {
    /// Opaque palette token for the surface — replaces the translucent fill
    /// when High Contrast is on. The state parameter is reserved for future
    /// per-phase variants; v1 returns a single opaque system surface
    /// regardless of state, with state info carried by `contrastedStroke`.
    static func contrastedFill(for state: HaloPhase) -> Color {
        _ = state
        // System window background is the canonical opaque-surface token; it
        // tracks Light/Dark and the system "Increase contrast" pass.
        return Color(nsColor: .windowBackgroundColor)
    }

    /// 1pt solid stroke in the state's accent color (spec §6.4 "inner strokes
    /// become 1pt solid"). Returns the same color the halo glow would use,
    /// at full opacity, so state remains readable when the glow is suppressed.
    static func contrastedStroke(for state: HaloPhase) -> Color {
        state.glowColor
    }

    /// `true` → suppress the outer halo glow under High Contrast. The 1pt
    /// solid `contrastedStroke` carries the state indication instead.
    static let contrastedHaloDisabled: Bool = true
}

// MARK: - Previews

#if DEBUG
private struct HaloMaterialPreview: View {
    let appearance: GlassAppearance
    let phase: HaloPhase

    var body: some View {
        HaloMaterial(
            shape: RoundedRectangle(cornerRadius: 22, style: .continuous),
            phase: phase,
            breathePulse: phase == .enhancing ? 0.6 : 0,
            showInnerSheen: phase == .enhancing,
            appearance: appearance
        )
        .frame(width: 280, height: 56)
    }
}

// MARK: - 7-state previews (spec §4)
//
// One preview per conceptual state in the Sotto 7-state morphology:
//   idle / arming / recording / transcribing / enhancing / committed / fail.
// `idle` is intentionally rendered as `.hidden` against the onyx backdrop so
// reviewers see "panel is unmounted / no glow" — the production idle behavior
// is `orderOut` + SwiftUI subtree unmount at the window-manager layer
// (`NotchWindowManager.hide`), not an ambient surface.

#Preview("Onyx — idle (hidden / orderOut)") {
    HaloMaterialPreview(appearance: .onyx, phase: .hidden)
        .padding(40)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Onyx — arming (breathing lime)") {
    HaloMaterialPreview(appearance: .onyx, phase: .armed)
        .padding(40)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Onyx — recording (red dot)") {
    HaloMaterialPreview(appearance: .onyx, phase: .recording)
        .padding(40)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Onyx — transcribing (cyan sweep)") {
    HaloMaterialPreview(appearance: .onyx, phase: .transcribing)
        .padding(40)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Onyx — enhancing (violet breath)") {
    HaloMaterialPreview(appearance: .onyx, phase: .enhancing)
        .padding(40)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Onyx — committed (green confirm)") {
    HaloMaterialPreview(appearance: .onyx, phase: .done)
        .padding(40)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Onyx — fail (red blink)") {
    HaloMaterialPreview(appearance: .onyx, phase: .failed)
        .padding(40)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Light — recording") {
    HaloMaterialPreview(appearance: .light, phase: .recording)
        .padding(40)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}

#Preview("Light — enhancing") {
    HaloMaterialPreview(appearance: .light, phase: .enhancing)
        .padding(40)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
