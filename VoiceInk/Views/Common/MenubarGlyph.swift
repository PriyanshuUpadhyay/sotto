import SwiftUI
import AppKit

// MARK: - MenubarGlyph
//
// Pure-SwiftUI two-stroke brand mark drawn via Canvas/Path. Spec §5.2.
//
// 18×18pt canvas. Mark (vertical bar) renders Color.primary so it auto-flips
// against light/dark menubars. Underscore stays Palette.brandAcid in both
// modes per §5.3 (lime is the brand-mark; non-template at every menubar size).
//
// Per-state overlays (BouncingDots, ArcSpinner, CornerBadge, FailGlyph) are
// composited via MenubarGlyphContainer's ZStack. This struct draws ONLY the
// base mark + underscore.
//
// Accessibility-label generation is exposed as a pure-logic static function so
// each label is testable without SwiftUI runtime (XCTest-friendly).

struct MenubarGlyph: View {
    /// 0…1 — caller-supplied alpha for breathe motion (arming state). Default 1.0.
    var alpha: Double = 1.0

    /// Whether the mark fills (recording = solid bar) or strokes (hollow during
    /// enhancing per §4.2 row 5). Default solid.
    var markFilled: Bool = true

    /// Whether the underscore renders. Reserved for future ghost-idle treatment;
    /// always true at v1.
    var underscoreVisible: Bool = true

    // Spec §5.2 — proportions exposed as static constants for test access.
    static let markWidthRatio: CGFloat = 0.18
    static let markHeightRatio: CGFloat = 0.55
    static let underscoreWidthRatio: CGFloat = 1.00
    static let underscoreHeightRatio: CGFloat = 0.14
    static let gapRatio: CGFloat = 0.08

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let totalH = (Self.markHeightRatio + Self.gapRatio + Self.underscoreHeightRatio) * s
            let topInset = (s - totalH) / 2.0

            let markW = Self.markWidthRatio * s
            let markH = Self.markHeightRatio * s
            let markRect = CGRect(
                x: (s - markW) / 2.0,
                y: topInset,
                width: markW,
                height: markH
            )
            let mark = Path(roundedRect: markRect, cornerRadius: markW * 0.15)
            if markFilled {
                ctx.fill(mark, with: .color(Color.primary.opacity(alpha)))
            } else {
                ctx.stroke(mark, with: .color(Color.primary.opacity(alpha)), lineWidth: 1.2)
            }

            guard underscoreVisible else { return }
            let usY = topInset + markH + Self.gapRatio * s
            let usH = Self.underscoreHeightRatio * s
            let usRect = CGRect(x: 0, y: usY, width: s, height: usH)
            let us = Path(roundedRect: usRect, cornerRadius: usH * 0.3)
            ctx.fill(us, with: .color(Palette.brandAcid.opacity(alpha)))
        }
        .frame(width: 18, height: 18)
    }

    // MARK: - Accessibility-label (pure logic, exhaustive over IconState)
    //
    // Compiler-enforced switch: adding a new IconState case forces an update
    // here. MenuBarIcon composes this with the unresolved-failure suffix.

    static func accessibilityLabel(for state: MenuBarIconRenderer.IconState) -> String {
        switch state {
        case .idle:         return "Sotto idle"
        case .arming:       return "Sotto listening"
        case .recording:    return "Sotto recording"
        case .transcribing: return "Sotto transcribing"
        case .enhancing:    return "Sotto enhancing"
        case .committed:    return "Sotto committed"
        case .fail:         return "Sotto failed"
        case .handsFree:    return "Sotto hands-free"
        }
    }
}

// MARK: - State overlays
//
// Each overlay is a self-contained TimelineView-driven SwiftUI view. They
// composite on top of (or in place of) MenubarGlyph in MenubarGlyphContainer.

/// Transcribing state — 3 dots, vertical phase-offset translation. Spec §4.2 row 4.
struct BouncingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t + Double(i) * 0.18).truncatingRemainder(dividingBy: 0.9) / 0.9
                    let dy = sin(phase * 2 * .pi) * 2.0
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 3.2, height: 3.2)
                        .offset(y: -dy)
                }
            }
            .frame(width: 18, height: 18)
        }
    }
}

/// Enhancing state — 270° arc rotating 1.6s linear over a hollow mark. Spec §4.2 row 5.
struct ArcSpinner: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6 * 360
            Canvas { ctx, size in
                let s = min(size.width, size.height)
                let inset: CGFloat = 2.5
                let rect = CGRect(
                    x: (size.width - s) / 2 + inset,
                    y: (size.height - s) / 2 + inset,
                    width: s - inset * 2,
                    height: s - inset * 2
                )
                var path = Path()
                path.addArc(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width / 2,
                    startAngle: .degrees(angle),
                    endAngle: .degrees(angle + 270),
                    clockwise: false
                )
                ctx.stroke(path, with: .color(Color.primary), lineWidth: 1.2)
            }
            .frame(width: 18, height: 18)
        }
    }
}

/// Recording (red pulse) / committed (green static) / unresolved-failures (red
/// static) corner dot. Drawn upper-right of the 18pt canvas. Spec §4.2 rows 3, 6.
struct CornerBadge: View {
    enum Kind {
        case redPulse, greenStatic, redStatic
        var color: Color {
            switch self {
            case .redPulse, .redStatic: return Palette.recRed
            case .greenStatic:          return Palette.commitGreen
            }
        }
    }

    let kind: Kind

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let alpha: Double = {
                switch kind {
                case .redPulse:
                    return 0.5 + 0.5 * sin(t * 2 * .pi)
                case .greenStatic, .redStatic:
                    return 1.0
                }
            }()
            ZStack(alignment: .topTrailing) {
                Color.clear
                Circle()
                    .fill(kind.color.opacity(alpha))
                    .frame(width: 4, height: 4)
                    .padding(.top, 1)
                    .padding(.trailing, 1)
            }
            .frame(width: 18, height: 18)
        }
    }
}

/// Fail state — red `!` overlay + red corner badge. Spec §4.2 row 7.
struct FailGlyph: View {
    var body: some View {
        ZStack {
            Text("!")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Palette.recRed)
            CornerBadge(kind: .redStatic)
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: - MenubarGlyphContainer
//
// Routes IconState → composed view. This is the surface MenuBarIcon hosts
// inside the MenuBarExtra label closure. Switch is exhaustive over IconState
// — adding a new case is a compile error here.

struct MenubarGlyphContainer: View {
    let state: MenuBarIconRenderer.IconState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch state {
        case .idle:
            MenubarGlyph()
        case .arming:
            if reduceMotion {
                MenubarGlyph(alpha: 0.75)
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let breathe = 0.55 + 0.45 * (sin(t * 2 * .pi / 1.2) + 1) / 2
                    MenubarGlyph(alpha: breathe)
                }
            }
        case .recording:
            ZStack {
                MenubarGlyph(markFilled: true)
                if reduceMotion {
                    CornerBadge(kind: .redStatic)
                } else {
                    CornerBadge(kind: .redPulse)
                }
            }
        case .transcribing:
            BouncingDots()
        case .enhancing:
            ZStack {
                MenubarGlyph(markFilled: false)
                if !reduceMotion {
                    ArcSpinner()
                }
            }
        case .committed:
            ZStack {
                MenubarGlyph()
                CornerBadge(kind: .greenStatic)
            }
        case .fail:
            FailGlyph()
        case .handsFree:
            // Hands-free affordance preserved via legacy NSImage builder.
            Image(nsImage: MenuBarIconRenderer.image(for: .handsFree))
        }
    }
}

// MARK: - Previews

#if DEBUG
private struct MenubarStatePreviewGrid: View {
    var body: some View {
        let states: [MenuBarIconRenderer.IconState] = [
            .idle, .arming, .recording, .transcribing,
            .enhancing, .committed, .fail, .handsFree
        ]
        VStack(spacing: 14) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, s in
                HStack {
                    Text(String(describing: s))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 100, alignment: .leading)
                    MenubarGlyphContainer(state: s).frame(width: 18, height: 18)
                    MenubarGlyphContainer(state: s).frame(width: 64, height: 64)
                }
            }
        }
        .padding(24)
    }
}

#Preview("MenubarGlyph — All states Dark") {
    MenubarStatePreviewGrid()
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("MenubarGlyph — All states Light") {
    MenubarStatePreviewGrid()
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
