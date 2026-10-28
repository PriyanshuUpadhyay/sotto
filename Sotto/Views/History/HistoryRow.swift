import SwiftUI
import AppKit

// MARK: - History Row

struct HistoryRow: View {
    let transcription: Transcription
    @Binding var isExpanded: Bool
    let onShowInfo: () -> Void

    @State private var selectedTab: TranscriptionTab = .original

    private var displayText: String {
        switch selectedTab {
        case .original:
            return transcription.text
        case .enhanced:
            return transcription.enhancedText ?? ""
        }
    }

    private var audioURL: URL? {
        guard let urlString = transcription.audioFileURL,
              let url = URL(string: urlString),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            details
        } label: {
            summary
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Time only — the day section header already names the day.
            Text(transcription.timestamp, format: .dateTime.hour().minute())
                .font(.mono(11))
                .tabularNumbers()
                .foregroundStyle(.secondary)

            if !isExpanded {
                Text(transcription.enhancedText ?? transcription.text)
                    .font(.transcript(15))
                    .lineSpacing(3)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, 4)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if transcription.enhancedText != nil {
                    Picker("Version", selection: $selectedTab) {
                        ForEach(TranscriptionTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                CopyIconButton(textToCopy: displayText)
            }

            Text(displayText)
                .font(.transcript(15))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let audioURL {
                AudioPlayerView(url: audioURL, transcription: transcription, onInfoTap: onShowInfo)
                    .padding(.vertical, 4)
            } else {
                HStack {
                    Spacer()
                    Button("View details", systemImage: "info.circle", action: onShowInfo)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("View details")
                }
            }
        }
        .padding(.vertical, 6)
    }
}
