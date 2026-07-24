import SwiftUI
import AppKit

// MARK: - ConstellationLayout
//
// Anchor + layout geometry for the floating mini / external recorder. The strip
// is pinned to the screen BOTTOM and the cluster sits `anchorBelowBottom` above
// it. Shared between the cluster (anchor positioning) and the host panels.

struct ConstellationLayout {
    let mode: HaloShape.Mode
    let screenWidth: CGFloat

    /// Height of the host panel strip (single source of truth — the Mini
    /// RecorderPanel derives its frame height from this). Tall enough to clear
    /// the cluster + the `ReviewTray` above it without clipping.
    static let panelHeight: CGFloat = 190

    /// Cluster sits this far above the strip's bottom edge. Leaves room for the
    /// `.failed` action row (RETRY / OPEN SETTINGS).
    static let anchorBelowBottom: CGFloat = 50

    /// `ReviewTray` bottom-edge inset above the strip bottom — a ~18pt gap above
    /// the pill's top so the bottom-pinned tray grows UPWARD.
    static let liveCardBottomInset: CGFloat = 83

    static func current(mode: HaloShape.Mode) -> ConstellationLayout {
        resolve(mode: mode, screenWidth: NSScreen.active?.frame.width ?? 1440)
    }

    static func resolve(mode: HaloShape.Mode, screenWidth: CGFloat) -> ConstellationLayout {
        ConstellationLayout(mode: mode, screenWidth: screenWidth)
    }

    var anchorX: CGFloat { screenWidth / 2 }

    /// Topleading-space y (measured DOWN from the strip's top edge): the cluster
    /// centre sits `anchorBelowBottom` above the strip bottom.
    var anchorY: CGFloat {
        switch mode {
        case .floating:
            return Self.panelHeight - Self.anchorBelowBottom
        }
    }
}
