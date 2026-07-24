import SwiftUI

// MARK: - HaloRecorderView
//
// Thin adapter — used to be a 580 LOC pill renderer; in P1.G it became a
// pass-through, and in P2 it hosts the matte recorder capsule
// (`MatteCapsuleContainer`) as the recorder root, retiring the Constellation
// pill. `MiniWindowManager` keeps its existing constructor, so no call site is
// touched.
//
// The capsule container owns the 4 functional states + their motion
// (Reduce-Motion safe) and Dock-safe placement. `aiService` / `mode` remain in
// the signature for call-site compatibility but no longer drive the body.

struct HaloRecorderView<S: RecorderStateProvider & ObservableObject, WM: ObservableObject>: View {
    @ObservedObject var stateProvider: S
    // De-observed (perf): this root host only FORWARDS `recorder` to the capsule
    // container and never reads a property. If it @ObservedObject'd recorder,
    // `audioMeter`'s ~60Hz publish would re-evaluate this body every frame,
    // defeating the downstream de-observe.
    let recorder: Recorder
    @ObservedObject var aiService: AIService
    @ObservedObject var windowManager: WM
    var isVisible: () -> Bool
    var mode: HaloShape.Mode

    var body: some View {
        if isVisible() {
            MatteCapsuleContainer(
                stateProvider: stateProvider,
                recorder: recorder
            )
        }
    }
}

