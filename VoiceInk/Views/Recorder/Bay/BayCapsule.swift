import SwiftUI

struct BayCapsule: View {
    @ObservedObject var ui: RecorderUIState

    var body: some View {
        TacticalGlass.bay(phase: ui.phase)
            .overlay(content)
    }

    @ViewBuilder
    private var content: some View {
        switch ui.phase {
        case .hidden:           EmptyView()
        case .armed:            ArmingContent(ui: ui)
        case .recording, .liveText: RecordingContent(ui: ui)
        case .transcribing:     TranscribingContent(ui: ui)
        case .enhancing:        EnhancingContent(ui: ui)
        case .done:             CommittedContent(ui: ui)
        case .failed:           FailContent(ui: ui)
        }
    }
}

// Placeholder content views — implemented in milestone m03.
struct TranscribingContent: View{ @ObservedObject var ui: RecorderUIState; var body: some View { Color.clear } }
struct EnhancingContent: View   { @ObservedObject var ui: RecorderUIState; var body: some View { Color.clear } }
struct CommittedContent: View   { @ObservedObject var ui: RecorderUIState; var body: some View { Color.clear } }
struct FailContent: View        { @ObservedObject var ui: RecorderUIState; var body: some View { Color.clear } }
