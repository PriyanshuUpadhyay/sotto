import SwiftUI

// MARK: - HaloRecorderView
//
// Thin adapter — used to be a 580 LOC pill renderer; in P1.G it became a
// pass-through to `ConstellationContainer` so both window managers
// (`NotchWindowManager`, `MiniWindowManager`) keep their existing
// constructor and we don't have to touch every call site at once.
//
// The constellation pieces (orb, chip, card, whisper line) own all
// per-state visuals + motion. The breathe pulse, popover plumbing,
// minPillWidth / maxPillWidth math, the `pill`/`mainRow`/`liveTextPanel`
// stack, the `RecordingDot` / `TranscribingShimmerDot` glyphs, and the
// `EnhancingIdentity` view that lived in v1 are all gone.

struct HaloRecorderView<S: RecorderStateProvider & ObservableObject, WM: ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    @ObservedObject var windowManager: WM
    var isVisible: () -> Bool
    var mode: HaloShape.Mode

    var body: some View {
        if isVisible() {
            if mode == .notch {
                BayHUDViewHost(
                    stateProvider: stateProvider,
                    recorder: recorder,
                    aiService: aiService
                )
            } else {
                ConstellationContainer(
                    stateProvider: stateProvider,
                    recorder: recorder,
                    aiService: aiService,
                    mode: mode
                )
            }
        }
    }
}

private struct BayHUDViewHost<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    @EnvironmentObject var uiManager: RecorderUIManager

    var body: some View {
        BayHUDView(
            stateProvider: stateProvider,
            recorder: recorder,
            aiService: aiService,
            uiManager: uiManager
        )
    }
}

