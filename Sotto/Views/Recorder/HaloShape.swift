import SwiftUI

// MARK: - HaloShape
//
// An all-around rounded pill for the floating recorder.
//
// Animatable corner radii so morph transitions feel like one continuous body.

struct HaloShape: Shape {
    enum Mode: Equatable {
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
        case .floating: return floatingPath(in: rect)
        }
    }

    // All-around rounded pill, asymmetric top/bottom radii.
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
