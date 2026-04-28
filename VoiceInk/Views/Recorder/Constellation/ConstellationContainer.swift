import SwiftUI
import AppKit

// MARK: - ConstellationContainer
//
// Thin shim — preserves the constructor surface used by NotchWindowManager /
// MiniWindowManager / HaloRecorderView so panel hosts aren't touched. All
// visual + state logic lives in `ConstellationCluster` (W2).

struct ConstellationContainer<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    let mode: HaloShape.Mode

    var body: some View {
        ConstellationCluster(
            stateProvider: stateProvider,
            recorder: recorder,
            aiService: aiService,
            mode: mode
        )
    }
}

// MARK: - ConstellationLayout
//
// Anchor + layout geometry. Shared between the cluster (anchor positioning)
// and any future host adapters. Spec §2: anchor centred horizontally below
// the notch (or virtual notch on non-notch displays), 50pt below the menu-bar
// baseline.

struct ConstellationLayout {
    let isNotched: Bool
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let screenWidth: CGFloat

    /// 50pt below menu-bar baseline (spec §2).
    static let anchorBelowMenubar: CGFloat = 50

    static func current(mode: HaloShape.Mode) -> ConstellationLayout {
        guard let screen = NSScreen.main else {
            return ConstellationLayout(
                isNotched: false,
                notchHeight: 24,
                notchWidth: 0,
                screenWidth: 1440
            )
        }
        let safeTop = screen.safeAreaInsets.top
        let isNotched = safeTop > 0
        let notchHeight: CGFloat = isNotched
            ? safeTop
            : NSStatusBar.system.thickness
        let notchWidth: CGFloat = {
            if let l = screen.auxiliaryTopLeftArea?.width,
               let r = screen.auxiliaryTopRightArea?.width {
                return screen.frame.width - l - r
            }
            return 180
        }()
        return ConstellationLayout(
            isNotched: isNotched && mode == .notch,
            notchHeight: notchHeight,
            notchWidth: notchWidth,
            screenWidth: screen.frame.width
        )
    }

    var anchorX: CGFloat { screenWidth / 2 }
    var anchorY: CGFloat { notchHeight + Self.anchorBelowMenubar }
}
