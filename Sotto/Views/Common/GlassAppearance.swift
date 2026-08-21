import SwiftUI
import AppKit
import Combine
import os.signpost

// MARK: - GlassAppearance
//
// Two-variant adaptive glass material vocabulary. Selected by
// `GlassAppearanceDetector` per spec §2.3 + §6.1: hybrid wallpaper-luminance
// detection. System appearance is the default; a bright top-strip on the
// active screen's wallpaper overrides to `.light`.

enum GlassAppearance: Equatable {
    case onyx   // dark variant — default for recorder, dark-mode surfaces
    case light  // light variant — bright wallpapers, light-mode surfaces
}

// MARK: - GlassAppearanceDetector
//
// Samples the active screen's wallpaper top strip (60pt) once at launch and
// on `NSWorkspace.activeSpaceDidChangeNotification`. Average luminance > 0.6
// flips to `.light`; otherwise falls back to system effective appearance.
//
// Cleans up its workspace observer in `deinit` (no leaks). Sampling cost is
// instrumented via `os_signpost` so the ~15ms per-screen-change claim is
// verifiable in Instruments. Defaults to `.onyx` so views render with the
// existing recorder look until sampling completes.

@MainActor
final class GlassAppearanceDetector: ObservableObject {
    static let shared = GlassAppearanceDetector()

    @Published private(set) var current: GlassAppearance = .onyx

    private var spaceObserver: NSObjectProtocol?
    private var wallpaperObserver: NSObjectProtocol?
    private var systemAppearanceObserver: NSKeyValueObservation?
    private var appearanceChoiceCancellable: AnyCancellable?

    private static let signposter = OSSignposter(subsystem: "com.sotto.glass", category: "appearance")

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        spaceObserver = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        wallpaperObserver = center.addObserver(
            forName: NSNotification.Name("NSWorkspaceDesktopImageDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        systemAppearanceObserver = NSApplication.shared.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        appearanceChoiceCancellable = AppearanceStore.shared.$choice
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        refresh()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        if let obs = spaceObserver { center.removeObserver(obs) }
        if let obs = wallpaperObserver { center.removeObserver(obs) }
    }

    /// Re-sample wallpaper luminance + system appearance and publish the result.
    func refresh() {
        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("sampleAppearance", id: signpostID)
        let next = sampleAppearance()
        Self.signposter.endInterval("sampleAppearance", state)
        if next != current { current = next }
    }

    private func sampleAppearance() -> GlassAppearance {
        if let forced = AppearanceStore.shared.choice.glassAppearance {
            return forced
        }
        guard let screen = NSScreen.main else { return systemFallback() }
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return systemFallback()
        }
        guard let lum = topStripLuminance(url: url) else {
            return systemFallback()
        }
        // Only luminance > 0.6 forces `.light`. Dim wallpapers fall through to
        // system appearance so the user's Light/Dark preference still wins
        // (spec §6.1, plan §P1.A reviewer-focus: do NOT hardcode `.onyx` here).
        return lum > 0.6 ? .light : systemFallback()
    }

    private func systemFallback() -> GlassAppearance {
        guard let app = NSApp,
              let match = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        else { return .onyx }
        return match == .aqua ? .light : .onyx
    }

    /// Compute average Rec. 709 luminance of the wallpaper's top 60pt strip.
    /// Downsamples to 32px wide for speed — full-fidelity sampling isn't
    /// needed for a binary threshold.
    private func topStripLuminance(url: URL) -> Double? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }

        let imgW = cg.width
        let imgH = cg.height
        guard imgW > 0, imgH > 0 else { return nil }

        // 60pt strip → proportional pixel rows. Wallpapers are typically
        // sized to screen height; the ratio holds well enough for a luminance
        // threshold without per-screen geometry math.
        let screenH = NSScreen.main?.frame.height ?? 1080
        let stripPx = max(1, min(imgH, Int(60.0 / screenH * Double(imgH))))

        guard let crop = cg.cropping(to: CGRect(x: 0, y: 0, width: imgW, height: stripPx))
        else { return nil }

        // Downsample to 32 wide for speed.
        let targetW = 32
        let targetH = max(1, Int(Double(crop.height) * Double(targetW) / Double(crop.width)))
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * targetW
        var pixels = [UInt8](repeating: 0, count: targetW * targetH * bytesPerPixel)
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: &pixels,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        var sum = 0.0
        let count = targetW * targetH
        for i in 0..<count {
            let r = Double(pixels[i * 4 + 0]) / 255.0
            let g = Double(pixels[i * 4 + 1]) / 255.0
            let b = Double(pixels[i * 4 + 2]) / 255.0
            sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        return sum / Double(count)
    }
}
