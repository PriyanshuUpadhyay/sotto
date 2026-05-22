import SwiftUI

struct TranscribingContent: View {
    @ObservedObject var ui: RecorderUIState

    var body: some View {
        ZStack {
            CyanSweep()
            HStack(spacing: 10) {
                AudioBars(level: ui.audioLevel, frozen: true, tint: Palette.transCyan)
                MonoLabel(text: "TRANSCRIBING…", size: 10.5, color: Palette.transCyan)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transcribing")
    }
}
