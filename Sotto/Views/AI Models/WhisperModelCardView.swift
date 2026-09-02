import SwiftUI
import AppKit
// MARK: - Local Model Card View
struct WhisperModelCardView: View {
    let model: WhisperModel
    let isDownloaded: Bool
    let isCurrent: Bool
    let downloadProgress: [String: Double]
    let downloadError: String?
    let modelURL: URL?
    let isWarming: Bool
    
    // Actions
    var deleteAction: () -> Void
    var setDefaultAction: () -> Void
    var downloadAction: () -> Void
    private var isDownloading: Bool {
        downloadProgress.keys.contains(model.name + "_main") || 
        downloadProgress.keys.contains(model.name + "_coreml")
    }
    
    var body: some View {
        OnyxSurfaceCard(cornerRadius: Radius.control, padding: 16) {
            HStack(alignment: .top, spacing: 16) {
                // Main Content
                VStack(alignment: .leading, spacing: 6) {
                    headerSection
                    metadataSection
                    descriptionSection
                    progressSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Action Controls
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
            
            Spacer()
        }
    }
    
    private var metadataSection: some View {
        HStack(spacing: 12) {
            // Language
            Label(model.language, systemImage: "globe")
                .font(.system(size: 11))
                .foregroundColor(Palette.inkSecondary)
                .lineLimit(1)
            
            // Size
            Label(model.size, systemImage: "internaldrive")
                .font(.system(size: 11))
                .foregroundColor(Palette.inkSecondary)
                .lineLimit(1)
            
            // Speed
            HStack(spacing: 3) {
                Text("Speed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.inkSecondary)
                progressDotsWithNumber(value: model.speed * 10)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            
            // Accuracy
            HStack(spacing: 3) {
                Text("Accuracy")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.inkSecondary)
                progressDotsWithNumber(value: model.accuracy * 10)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
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
    
    private var progressSection: some View {
        Group {
            if isDownloading {
                DownloadProgressView(
                    modelName: model.name,
                    downloadProgress: downloadProgress
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
        Button(action: downloadAction) {
            HStack(spacing: 4) {
                Text(isDownloading ? "Downloading..." : (downloadError == nil ? "Download" : "Retry"))
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: downloadError == nil ? "arrow.down.circle" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
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
                // Selected but UNUSABLE — the key confusing state. Make it
                // self-explanatory and one-click-fixable.
                ModelStateBadge.selectedNotDownloaded
                downloadButton
            } else if isDownloaded {
                if isWarming {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Optimizing model for your device...")
                            .font(.system(size: 12))
                            .foregroundColor(Palette.inkSecondary)
                    }
                } else {
                    ModelStateBadge.downloaded
                    Button(action: setDefaultAction) {
                        Text("Set as Default")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                downloadButton
            }

            if isDownloaded {
                Menu {
                    Button(action: deleteAction) {
                        Label("Delete Model", systemImage: "trash")
                    }
                    
                    Button {
                        if let modelURL = modelURL {
                            NSWorkspace.shared.selectFile(modelURL.path, inFileViewerRootedAtPath: "")
                        }
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

// MARK: - Imported Local Model (minimal UI)
struct ImportedWhisperModelCardView: View {
    let model: ImportedWhisperModel
    let isDownloaded: Bool
    let isCurrent: Bool
    let modelURL: URL?

    var deleteAction: () -> Void
    var setDefaultAction: () -> Void

    var body: some View {
        OnyxSurfaceCard(cornerRadius: Radius.control, padding: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Palette.inkPrimary)
                        Spacer()
                    }

                    Text("Imported local model")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if isCurrent {
                        Text("Default Model")
                            .font(.system(size: 12))
                            .foregroundColor(Palette.inkSecondary)
                    } else if isDownloaded {
                        Button(action: setDefaultAction) {
                            Text("Set as Default")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if isDownloaded {
                        Menu {
                            Button(action: deleteAction) {
                                Label("Delete Model", systemImage: "trash")
                            }
                            Button {
                                if let modelURL = modelURL {
                                    NSWorkspace.shared.selectFile(modelURL.path, inFileViewerRootedAtPath: "")
                                }
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
        // Selection ring only — OnyxSurfaceCard already strokes its own
        // hairline, and the radius stays concentric with the card around it.
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Brand.tint.opacity(isCurrent ? 0.55 : 0), lineWidth: 1.5)
        )
    }
}


// MARK: - Model Download Error
//
// The cause of a failed download, rendered on the card that failed so a retry
// is not blind. Paired with the action column's Retry button.
struct ModelDownloadErrorLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundColor(Palette.stateFail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Download failed: \(message)")
    }
}

// MARK: - Model State Badge
//
// Shared, unmistakable state labels for the transcription model cards. Onyx
// tokens: recRed/warn for problem states, neutral for informational tags.
struct ModelStateBadge: View {
    enum Kind {
        case selectedNotDownloaded
        case downloaded
    }

    let kind: Kind

    static let selectedNotDownloaded = ModelStateBadge(kind: .selectedNotDownloaded)
    static let downloaded = ModelStateBadge(kind: .downloaded)

    var body: some View {
        switch kind {
        case .selectedNotDownloaded:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text("Selected · not downloaded")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(Palette.recRed)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.recRed.opacity(0.12))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Selected but not downloaded")
        case .downloaded:
            Text("Downloaded")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Helper Views and Functions

func progressDotsWithNumber(value: Double) -> some View {
    HStack(spacing: 4) {
        progressDots(value: value)
        Text(String(format: "%.1f", value))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(Palette.inkSecondary)
    }
}

func progressDots(value: Double) -> some View {
    HStack(spacing: 2) {
        ForEach(0..<5) { index in
            Circle()
                .fill(index < Int(value / 2) ? performanceColor(value: value / 10) : Color(.quaternaryLabelColor))
                .frame(width: 6, height: 6)
        }
    }
}

func performanceColor(value: Double) -> Color {
    switch value {
    case 0.8...1.0: return Palette.success
    case 0.6..<0.8: return Palette.warn
    case 0.4..<0.6: return Palette.stateFail
    default: return Palette.recRed
    }
}
