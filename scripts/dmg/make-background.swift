#!/usr/bin/env swift
// Generates the Sotto DMG installer-window background — refined onyx editorial
// in the Acid Lime brand palette (onyx #08080C, lime #D4FF3A). Renders @1x
// (640x440) and @2x PNGs, matching the icon positions in scripts/dmg/settings.py
// (Sotto {165,205}, Applications {475,205}, top-left origin). The window shows
// the top 640x400; the extra 40 rows are plain onyx so a Finder whose title
// bar is shorter than 32 pt never exposes the default white ground below the
// art. Everything a user must read sits above y=350 because a Finder with its
// tab bar shown loses another 39 rows at the bottom. Output: background.png +
// background@2x.png next to this file; dmgbuild folds both into one HiDPI TIFF.
import AppKit

let W: CGFloat = 640, H: CGFloat = 440

func srgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}
let onyx  = srgb(0x08, 0x08, 0x0C)
let onyx2 = srgb(0x0D, 0x0E, 0x12)        // faint cool lift, top of frame
let lime  = srgb(0xD4, 0xFF, 0x3A)
let white = NSColor.white

// Finder icon centers (top-left origin) → flip to bottom-left for drawing.
let iconY = H - 205                         // 235
let leftX:  CGFloat = 165
let rightX: CGFloat = 475
let arrowMidY = iconY
// Finder draws each label centred 83 pt below a 128 pt icon at text size 12
// (measured on macOS 26), in dark text regardless of appearance, so the art
// carries a light plate there.
let labelY = H - 288                        // 152
let plateSize = NSSize(width: 128, height: 28)

func font(_ names: [String], _ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    for n in names { if let f = NSFont(name: n, size: size) { return f } }
    return NSFont.systemFont(ofSize: size, weight: weight)
}

func render(scale: Int, to path: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(W) * scale, pixelsHigh: Int(H) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let full = NSRect(x: 0, y: 0, width: W, height: H)

    // 1. base: subtle vertical onyx gradient
    NSGradient(starting: onyx2, ending: onyx)!.draw(in: full, angle: -90)

    // 2. edge vignette for depth (before the glow so the glow stays crisp)
    let vig = NSGradient(colors: [NSColor.black.withAlphaComponent(0),
                                  NSColor.black.withAlphaComponent(0.45)])!
    vig.draw(in: full, relativeCenterPosition: .zero)

    // 4. fine deterministic grain (kills banding, adds texture)
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func rnd() -> Double { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return Double(seed % 1000) / 1000.0 }
    var gx: CGFloat = 0
    while gx < W { var gy: CGFloat = 0
        while gy < H {
            let v = rnd()
            (v > 0.5 ? white : NSColor.black).withAlphaComponent(0.022).setFill()
            NSBezierPath(rect: NSRect(x: gx, y: gy, width: 1.5, height: 1.5)).fill()
            gy += 2 }
        gx += 2 }

    // 5. label plates under both icons (before the glow so their edges stay crisp)
    for cx in [leftX, rightX] {
        let r = NSRect(x: cx - plateSize.width/2, y: labelY - plateSize.height/2,
                       width: plateSize.width, height: plateSize.height)
        let plate = NSBezierPath(roundedRect: r, xRadius: plateSize.height/2, yRadius: plateSize.height/2)
        srgb(0xF1, 0xF3, 0xEA).setFill(); plate.fill()
        lime.withAlphaComponent(0.5).setStroke(); plate.lineWidth = 1; plate.stroke()
    }

    // 6. arrow: motion-trail dashes + slim shaft + clean chevron, lime glow
    let shaftStart = leftX + 86
    let tipX       = rightX - 92
    let shaftEnd   = tipX - 18

    let glow = NSShadow()
    glow.shadowColor = lime.withAlphaComponent(0.65); glow.shadowBlurRadius = 16; glow.shadowOffset = .zero
    glow.set()
    lime.setStroke(); lime.setFill()

    // trailing dashes (fading) imply motion
    for (i, dx) in [CGFloat(-34), -54, -72].enumerated() {
        let d = NSBezierPath()
        d.lineWidth = 6; d.lineCapStyle = .round
        d.move(to: NSPoint(x: shaftStart + dx - 8, y: arrowMidY))
        d.line(to: NSPoint(x: shaftStart + dx + 4, y: arrowMidY))
        lime.withAlphaComponent(0.55 - CGFloat(i) * 0.16).setStroke()
        d.stroke()
    }
    lime.setStroke()
    let shaft = NSBezierPath()
    shaft.lineWidth = 7; shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: shaftStart, y: arrowMidY))
    shaft.line(to: NSPoint(x: shaftEnd, y: arrowMidY))
    shaft.stroke()

    let head = NSBezierPath()
    let hw: CGFloat = 22
    head.move(to: NSPoint(x: tipX, y: arrowMidY))
    head.line(to: NSPoint(x: shaftEnd - 2, y: arrowMidY + hw))
    head.line(to: NSPoint(x: shaftEnd + 8, y: arrowMidY))
    head.line(to: NSPoint(x: shaftEnd - 2, y: arrowMidY - hw))
    head.close()
    head.fill()

    // 7. typography (no glow)
    NSShadow().set()
    func draw(_ s: String, _ f: NSFont, _ c: NSColor, kern: CGFloat, topY: CGFloat) {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c, .kern: kern, .paragraphStyle: p]
        let str = NSAttributedString(string: s, attributes: a)
        let sz = str.size()
        str.draw(at: NSPoint(x: (W - sz.width)/2, y: H - topY - sz.height))
    }
    let body = font(["Avenir Next", "AvenirNext-Regular"], 12.5, .regular)
    let small = font(["Avenir Next", "AvenirNext-Regular"], 11, .regular)
    draw("INSTALL SOTTO", font(["Avenir Next Demi Bold", "AvenirNext-DemiBold"], 22, .semibold),
         white, kern: 3.5, topY: 44)
    draw("Drag Sotto into Applications, then open it from there.",
         body, srgb(0x9A, 0x9C, 0x96), kern: 0.4, topY: 78)
    draw("If macOS blocks it: System Settings › Privacy & Security › Open Anyway",
         small, srgb(0x74, 0x76, 0x70), kern: 0.3, topY: 98)
    draw("Requires macOS 26 · Apple silicon",
         small, srgb(0x5E, 0x60, 0x5A), kern: 0.6, topY: 330)

    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("png encode failed\n".data(using: .utf8)!); exit(1)
    }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(Int(W)*scale)x\(Int(H)*scale))")
}

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
render(scale: 1, to: "\(dir)/background.png")
render(scale: 2, to: "\(dir)/background@2x.png")
