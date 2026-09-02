import SwiftUI

// MARK: - PressableChipStyle
//
// Press feedback for the small chips on the floating recorder surfaces (retry,
// tray ghost actions, review version segments). These sit on non-activating
// panels where the user cannot tell whether a click will land, so the press
// itself — not just its result — has to acknowledge. Reduce Motion keeps the
// opacity dip and drops the scale (gentler, not absent).

struct PressableChipStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : MotionTokens.stateEnter, value: configuration.isPressed)
    }
}
