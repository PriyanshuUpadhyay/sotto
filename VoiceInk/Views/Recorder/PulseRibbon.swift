import SwiftUI

// MARK: - Pulse Ribbon
//
// A Catmull-Rom-smoothed audio waveform. 32 sample points held in a rolling
// buffer, redrawn every frame from `audioMeter.averagePower`. Active sample
// (newest) gets a halo dot at the right edge. Reads as breath, not bars.

struct PulseRibbon: View {
    @ObservedObject var recorder: Recorder
    var color: Color = .white
    var isActive: Bool = true
    /// Width budget for the ribbon. Pulse expands gracefully if larger.
    var width: CGFloat = 220
    var height: CGFloat = 22

    private let sampleCount = 32

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.033)) { context in
            Canvas { ctx, size in
                let samples = Self.samples(at: context.date,
                                            level: recorder.audioMeter.averagePower,
                                            count: sampleCount,
                                            isActive: isActive)
                drawRibbon(ctx: &ctx, size: size, samples: samples)
            }
            .frame(width: width, height: height)
        }
    }

    // Draw the ribbon path with a vertical gradient fill, then a soft halo at the active sample.
    private func drawRibbon(ctx: inout GraphicsContext, size: CGSize, samples: [CGFloat]) {
        guard samples.count >= 2 else { return }

        // Build a smoothed line through the sample points.
        var path = Path()
        let stepX = size.width / CGFloat(samples.count - 1)
        let midY = size.height / 2

        var pts: [CGPoint] = []
        for (i, s) in samples.enumerated() {
            let x = CGFloat(i) * stepX
            let amp = max(0.06, min(1, s))
            let y = midY - (amp * size.height * 0.45)
            pts.append(CGPoint(x: x, y: y))
        }

        // Top edge of the ribbon — Catmull-Rom-ish via quadratic curves through midpoints.
        path.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let mid = CGPoint(
                x: (pts[i].x + pts[i + 1].x) / 2,
                y: (pts[i].y + pts[i + 1].y) / 2
            )
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts.last ?? .zero)

        // Mirror to bottom for a closed ribbon.
        var mirror: [CGPoint] = []
        for p in pts.reversed() {
            mirror.append(CGPoint(x: p.x, y: size.height - p.y))
        }
        path.addLine(to: mirror.first ?? .zero)
        for i in 0..<(mirror.count - 1) {
            let mid = CGPoint(
                x: (mirror[i].x + mirror[i + 1].x) / 2,
                y: (mirror[i].y + mirror[i + 1].y) / 2
            )
            path.addQuadCurve(to: mid, control: mirror[i])
        }
        path.closeSubpath()

        // Fill with vertical gradient — brighter center, fade to edges.
        ctx.fill(path, with: .linearGradient(
            Gradient(stops: [
                .init(color: color.opacity(0.35), location: 0.0),
                .init(color: color.opacity(0.92), location: 0.5),
                .init(color: color.opacity(0.35), location: 1.0)
            ]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 0, y: size.height)
        ))

        // Active-sample halo — newest sample is the right edge.
        if isActive, let last = pts.last {
            let haloRect = CGRect(
                x: last.x - 4, y: size.height / 2 - 4,
                width: 8, height: 8
            )
            ctx.blendMode = .plusLighter
            ctx.fill(Path(ellipseIn: haloRect),
                     with: .color(color.opacity(0.6)))
            ctx.blendMode = .normal
        }
    }

    /// Generate a rolling sample window. Since AudioMeter exposes only the current
    /// average power, we synthesize plausible neighbors via a smooth wave modulated
    /// by the live level — gives the ribbon body and motion without holding history.
    static func samples(at date: Date, level: Double, count: Int, isActive: Bool) -> [CGFloat] {
        let amp = isActive ? max(0, min(1, pow(level, 0.65))) : 0
        let t = date.timeIntervalSince1970
        var out: [CGFloat] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let frac = Double(i) / Double(count - 1)
            // Wave 1: fast carrier — gives life.
            let w1 = sin(t * 7.0 + frac * 11.0) * 0.5 + 0.5
            // Wave 2: slow envelope — breath shape.
            let w2 = sin(t * 1.6 + frac * 3.5) * 0.5 + 0.5
            // Center boost — voice energy concentrates at the middle.
            let centerBoost = 1.0 - abs(frac - 0.5) * 0.6
            let combined = (w1 * 0.6 + w2 * 0.4) * centerBoost
            // Jitter on the right (newest) so the active dot wobbles.
            let edgeJitter = (frac > 0.85) ? sin(t * 13 + frac * 22) * 0.06 : 0
            out.append(CGFloat(0.06 + combined * amp + edgeJitter * amp))
        }
        return out
    }
}

// MARK: - Static Pulse — flat thread for idle-armed state

struct StaticPulse: View {
    var color: Color = .white
    var width: CGFloat = 140
    var height: CGFloat = 22

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let midY = size.height / 2
            path.move(to: CGPoint(x: 0, y: midY))
            path.addLine(to: CGPoint(x: size.width, y: midY))
            ctx.stroke(path,
                       with: .color(color.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        .frame(width: width, height: height)
    }
}
