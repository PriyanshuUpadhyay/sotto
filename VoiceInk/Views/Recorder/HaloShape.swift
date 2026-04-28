import SwiftUI

// MARK: - HaloShape
//
// A single shape that adapts its top edge:
//   - `.notch`: flat-top with small outward-curve corners that nest under the
//     physical MacBook notch. Identical silhouette to `NotchShape`.
//   - `.floating`: all-around rounded pill for non-notch / external displays.
//
// Animatable corner radii so morph transitions feel like one continuous body.

struct HaloShape: Shape {
    enum Mode: Equatable {
        case notch        // flat-top, outward-curving corners under physical notch
        case floating     // free-floating pill, top corners rounded
    }

    var mode: Mode
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    init(mode: Mode = .floating, topCornerRadius: CGFloat = 14, bottomCornerRadius: CGFloat = 18) {
        self.mode = mode
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        switch mode {
        case .notch:    return notchPath(in: rect)
        case .floating: return floatingPath(in: rect)
        }
    }

    // Mirrors NotchShape: top edge is flat (sits under physical notch), top corners
    // turn outward via quad curves, bottom corners are large rounded.
    private func notchPath(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }

    // All-around rounded pill, asymmetric top/bottom radii to keep continuity with the notch
    // variant in a morph between modes.
    private func floatingPath(in rect: CGRect) -> Path {
        let r = max(min(topCornerRadius, bottomCornerRadius), 1)
        let bottom = max(bottomCornerRadius, r)
        let top = max(topCornerRadius, r)

        var path = Path()
        // Top edge — left to right, with rounded corners.
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + top),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        // Right edge.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottom, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        // Bottom edge.
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottom),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        // Left edge.
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
