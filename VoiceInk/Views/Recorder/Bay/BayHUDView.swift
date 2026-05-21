import SwiftUI

// MARK: - BayHUDView
//
// Root of the Sotto notch HUD subtree. Mounts into the same NSHostingView
// rooted by NotchRecorderPanel.contentView — replaces ConstellationContainer
// for `.notch` mode only (`.mini` still uses ConstellationContainer).
//
// Layout (spec §2.2): three fixed-x-offset subviews on a ZStack the size of
// the full-width strip panel. Y-offset measured from top of panel
// (=top of screen, since NotchRecorderPanel is anchored to screen.maxY).

struct BayHUDView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    @ObservedObject var uiManager: RecorderUIManager
    @StateObject private var ui = RecorderUIState()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        let centerX = screenWidth / 2

        ZStack(alignment: .topLeading) {
            // Central capsule — 220×44, centered horizontally, 22pt from top.
            BayCapsule(ui: ui)
                .frame(width: 220, height: 44)
                .position(x: centerX, y: 22 + 22)   // y = top-offset + half-height

            // Left stalactite — 78×28, x = centerX − 118, y = 38 (+ half-height).
            BayLeftStalactite(ui: ui)
                .frame(width: 78, height: 28)
                .position(x: centerX - 118, y: 38 + 14)
                .allowsHitTesting(false)   // display-only

            // Right stalactite — 78×28, x = centerX + 118, y = 38.
            // Mouse-actionable — opt this subview out of the panel-wide
            // ignoresMouseEvents passthrough via .allowsHitTesting(true).
            BayRightStalactite(ui: ui)
                .frame(width: 78, height: 28)
                .position(x: centerX + 118, y: 38 + 14)
                .allowsHitTesting(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(ui.phase == .hidden ? 0 : 1)
        // Single withAnimation driver — every state change animates
        // capsule + both chips together.
        .animation(reduceMotion ? MotionTokens.reducedFade : MotionTokens.stateEnter,
                   value: ui.phase)
        .onAppear { syncFromManager() }
        .onChange(of: uiManager.phase) { _, _ in syncFromManager() }
        .onChange(of: stateProvider.recordingState) { _, _ in syncFromManager() }
        .onChange(of: recorder.audioMeter.averagePower) { _, lvl in
            ui.audioLevel = lvl
        }
    }

    private func syncFromManager() {
        ui.phase = uiManager.phase
        ui.recordingStartedAt = uiManager.recordingStartedAt
        ui.activePromptLabel = uiManager.formattedActivePromptLabel
        ui.errorCode = uiManager.currentErrorCode
        ui.lastPasteAppName = uiManager.lastPasteAppName
    }
}
