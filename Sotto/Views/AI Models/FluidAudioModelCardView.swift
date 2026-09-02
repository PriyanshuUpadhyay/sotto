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
            HStack(alignment: .top, spacing: 12) {
                // The row IS the selection control — one click switches engine.
                // Real-time, download and the ellipsis menu stay outside its
                // hit area so they never change the active model.
                Button(action: {
                    Task {
                        transcriptionModelManager.setDefaultTranscriptionModel(model)
                    }
                }) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            headerSection
                            metadataSection
                            descriptionSection
                            progressSection
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        statusSection
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .disabled(!isDownloaded)
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])

                trailingControls
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.displayName)
                .font(.ui(13, weight: .semibold))
                .foregroundColor(Palette.inkPrimary)

            if isCurrent && isDownloaded {
                ModelStateBadge.active
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
        .font(.ui(11))
        .foregroundColor(Palette.inkSecondary)
        .lineLimit(1)
    }

    private var descriptionSection: some View {
        Text(model.description)
            .font(.ui(11))
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

    /// The row's readiness, read as one chip. ACTIVE rides on the name, so this
    /// column only says whether the model can be chosen.
    @ViewBuilder
    private var statusSection: some View {
        if isCurrent && !isDownloaded {
            // Selected but UNUSABLE — the key confusing state.
            ModelStateBadge.selectedNotDownloaded
        } else if isDownloaded {
            ModelStateBadge.ready
        } else {
            ModelStateBadge.download(size: model.size)
        }
    }

    /// Controls that are NOT the selection: they sit outside the row button so
    /// downloading, switching to batch or opening the menu never switches the
    /// active model.
    private var trailingControls: some View {
        HStack(spacing: 8) {
            if model.supportsStreaming && isDownloaded {
                Toggle("Real-time", isOn: $streamingEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.ui(11, weight: .medium))
                    .foregroundColor(Palette.inkSecondary)
                    .onChange(of: streamingEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: streamingDefaultsKey)
                    }
                    .help(streamingEnabled ? "Live streaming enabled — click to switch to batch" : "Batch mode — click to enable live streaming")
                    .fixedSize()
            }

            if !isDownloaded {
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
