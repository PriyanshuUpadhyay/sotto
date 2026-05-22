import SwiftUI

struct RecordingContent: View {
    @ObservedObject var ui: RecorderUIState

    var body: some View {
        HStack(spacing: 10) {
            RecDot()
            AudioBars(level: ui.audioLevel, frozen: false, tint: Palette.brandAcid)
            if let startedAt = ui.recordingStartedAt {
                ElapsedLabel(startedAt: startedAt)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(axLabel)
    }

    private var axLabel: String {
        guard let started = ui.recordingStartedAt else { return "Recording" }
        let elapsed = Int(Date().timeIntervalSince(started))
        return "Recording, \(elapsed / 60) minutes \(elapsed % 60) seconds"
    }
}

private struct ElapsedLabel: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1.0)) { ctx in
            let elapsed = max(0, ctx.date.timeIntervalSince(startedAt))
            let m = Int(elapsed) / 60
            let s = Int(elapsed) % 60
            MonoLabel(text: String(format: "REC %02d:%02d", m, s), size: 10.5, color: Palette.brandAcid)
        }
    }
}
