import SwiftUI
import Combine
import AppKit

struct FluidAudioModelCardView: View {
    let model: FluidAudioModel
    @ObservedObject var fluidAudioModelManager: FluidAudioModelManager
    @ObservedObject var transcriptionModelManager: TranscriptionModelManager
    @State private var streamingEnabled: Bool

    init(model: FluidAudioModel, fluidAudioModelManager: FluidAudioModelManager, transcriptionModelManager: TranscriptionModelManager) {
        self.model = model
        _fluidAudioModelManager = ObservedObject(wrappedValue: fluidAudioModelManager)
        _transcriptionModelManager = ObservedObject(wrappedValue: transcriptionModelManager)
        let key = "streaming-enabled-\(model.name)"
        _streamingEnabled = State(initialValue: UserDefaults.standard.object(forKey: key) as? Bool ?? true)
    }

    private var streamingDefaultsKey: String {
        "streaming-enabled-\(model.name)"
    }

    var isCurrent: Bool {
        transcriptionModelManager.currentTranscriptionModel?.name == model.name
    }

    var isDownloaded: Bool {
        fluidAudioModelManager.isFluidAudioModelDownloaded(model)
    }

    var isDownloading: Bool {
        fluidAudioModelManager.isFluidAudioModelDownloading(model)
    }

    var body: some View {
        OnyxSurfaceCard(cornerRadius: Radius.control, padding: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    headerSection
                    metadataSection
                    descriptionSection
                    progressSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                actionSection
            }
        }
        // Selection ring only — OnyxSurfaceCard already strokes its own
        // hairline, and the radius stays concentric with the card around it.
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Brand.tint.opacity(isCurrent ? 0.55 : 0), lineWidth: 1.5)
        )
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.inkPrimary)

            if model.supportsStreaming && isDownloaded {
                Toggle("Real-time", isOn: $streamingEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.inkSecondary)
                    .onChange(of: streamingEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: streamingDefaultsKey)
                    }
                    .help(streamingEnabled ? "Live streaming enabled — click to switch to batch" : "Batch mode — click to enable live streaming")
            }

            Spacer()
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            Label(model.language, systemImage: "globe")
            Label(model.size, systemImage: "internaldrive")
            HStack(spacing: 3) {
                Text("Speed")
                progressDotsWithNumber(value: model.speed * 10)
            }
            .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 3) {
                Text("Accuracy")
                progressDotsWithNumber(value: model.accuracy * 10)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: 11))
        .foregroundColor(Palette.inkSecondary)
        .lineLimit(1)
    }

    private var descriptionSection: some View {
        Text(model.description)
            .font(.system(size: 11))
            .foregroundColor(Palette.inkSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private var downloadError: String? {
        fluidAudioModelManager.downloadErrors[model.name]
    }

    private var progressSection: some View {
        Group {
            if isDownloading {
                DownloadProgressView(
                    modelName: model.name,
                    downloadProgress: fluidAudioModelManager.downloadProgress,
                    isTwoPhase: false
                )
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let downloadError {
                ModelDownloadErrorLabel(message: downloadError)
                    .padding(.top, 8)
            }
        }
    }

    private var downloadButton: some View {
        Button(action: {
            Task {
                await fluidAudioModelManager.downloadFluidAudioModel(model)
            }
        }) {
            HStack(spacing: 4) {
                Text(isDownloading ? "Downloading..." : (downloadError == nil ? "Download" : "Retry"))
                Image(systemName: downloadError == nil ? "arrow.down.circle" : "arrow.clockwise")
            }
            .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(LimeFillButtonStyle())
        .disabled(isDownloading)
    }

    private var actionSection: some View {
        HStack(spacing: 8) {
            if isCurrent && isDownloaded {
                Text("Default Model")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.inkSecondary)
            } else if isCurrent && !isDownloaded {
                // Selected but UNUSABLE — the key confusing state.
                ModelStateBadge.selectedNotDownloaded
                downloadButton
            } else if isDownloaded {
                ModelStateBadge.downloaded
                Button(action: {
                    Task {
                        transcriptionModelManager.setDefaultTranscriptionModel(model)
                    }
                }) {
                    Text("Set as Default")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                downloadButton
            }

            if isDownloaded {
                Menu {
                    Button(action: {
                        fluidAudioModelManager.deleteFluidAudioModel(model)
                    }) {
                        Label("Delete Model", systemImage: "trash")
                    }

                    Button {
                        fluidAudioModelManager.showFluidAudioModelInFinder(model)
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }

                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            }
        }
    }
}
