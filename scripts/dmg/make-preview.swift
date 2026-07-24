#!/usr/bin/env swift
// Renders an OFFSCREEN preview of the installer window as a clean recipient
// (no toolbar, hidden helper files) would see it: the brand background +
// the real Sotto icon, the real Applications folder icon, and labels, inside
// a slim title-bar window chrome. No screen capture, no focus steal.
// Usage: swift make-preview.swift /path/to/Sotto.app  ->  preview.png
import AppKit

let appPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path

let W: CGFloat = 640, H: CGFloat = 400
let titleH: CGFloat = 28
let total = NSSize(width: W, height: H + titleH)

func centerImage(_ img: NSImage, finderX: CGFloat, finderY: CGFloat, side: CGFloat) {
    // Finder top-left origin → content drawn in bottom-left CG space (content
    // sits below the title bar, i.e. y in [0, H]).
    let cy = H - finderY
    img.draw(in: NSRect(x: finderX - side/2, y: cy - side/2, width: side, height: side),
             from: .zero, operation: .sourceOver, fraction: 1)
}
func label(_ s: String, finderX: CGFloat, topCG: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let a: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "Avenir Next", size: 12) ?? NSFont.systemFont(ofSize: 12),
        .foregroundColor: NSColor.white, .paragraphStyle: p,
        .shadow: { let s = NSShadow(); s.shadowColor = .black; s.shadowBlurRadius = 3; s.shadowOffset = .zero; return s }(),
    ]
    let str = NSAttributedString(string: s, attributes: a)
    let sz = str.size()
    str.draw(at: NSPoint(x: finderX - sz.width/2, y: topCG - sz.height))
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(total.width)*2, pixelsHigh: Int(total.height)*2,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = total
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx

// title bar
NSColor(white: 0.16, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: H, width: W, height: titleH)).fill()
for (i, c) in [NSColor(srgbRed:1,green:0.37,blue:0.34,alpha:1),
               NSColor(srgbRed:1,green:0.74,blue:0.18,alpha:1),
               NSColor(srgbRed:0.16,green:0.79,blue:0.25,alpha:1)].enumerated() {
    c.setFill(); NSBezierPath(ovalIn: NSRect(x: 14 + CGFloat(i)*20, y: H + titleH/2 - 6, width: 12, height: 12)).fill()
}
do {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    NSAttributedString(string: "Sotto", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: NSColor(white: 0.85, alpha: 1), .paragraphStyle: p])
        .draw(in: NSRect(x: 0, y: H + 6, width: W, height: 18))
}

// content background
if let bg = NSImage(contentsOfFile: "\(dir)/background.png") {
    bg.draw(in: NSRect(x: 0, y: 0, width: W, height: H), from: .zero, operation: .copy, fraction: 1)
}

// real icons
if let app = NSImage(contentsOfFile: "\(appPath)/Contents/Resources/AppIcon.icns") {
    centerImage(app, finderX: 165, finderY: 205, side: 128)
}
let appsIcon = NSWorkspace.shared.icon(forFile: "/Applications")
centerImage(appsIcon, finderX: 475, finderY: 205, side: 128)

// labels under icons (icon bottom in CG ≈ (H-205)-64 = 131)
label("Sotto", finderX: 165, topCG: 131 - 6)
label("Applications", finderX: 475, topCG: 131 - 6)

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "\(dir)/preview.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
