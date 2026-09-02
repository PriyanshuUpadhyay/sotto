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
            HStack(alignment: .top, spacing: 12) {
                // The row IS the selection control — one click switches engine.
                // Download and the ellipsis menu stay outside its hit area.
                Button(action: setDefaultAction) {
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
            // Language
            Label(model.language, systemImage: "globe")
                .font(.ui(11))
                .foregroundColor(Palette.inkSecondary)
                .lineLimit(1)
            
            // Size
            Label(model.size, systemImage: "internaldrive")
                .font(.ui(11))
                .foregroundColor(Palette.inkSecondary)
                .lineLimit(1)
            
            // Speed
            HStack(spacing: 3) {
                Text("Speed")
                    .font(.ui(11, weight: .medium))
                    .foregroundColor(Palette.inkSecondary)
                progressDotsWithNumber(value: model.speed * 10)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            
            // Accuracy
            HStack(spacing: 3) {
                Text("Accuracy")
                    .font(.ui(11, weight: .medium))
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
            .font(.ui(11))
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
                    .font(.ui(12, weight: .medium))
                Image(systemName: downloadError == nil ? "arrow.down.circle" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(LimeFillButtonStyle())
        .disabled(isDownloading)
    }

    /// The row's readiness, read as one chip. ACTIVE rides on the name, so this
    /// column only says whether the model can be chosen.
    @ViewBuilder
    private var statusSection: some View {
        if isCurrent && !isDownloaded {
            // Selected but UNUSABLE — the key confusing state. Kept as its own
            // explained badge; `trailingControls` carries the one-click fix.
            ModelStateBadge.selectedNotDownloaded
        } else if isDownloaded {
            if isWarming {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Optimizing model for your device...")
                        .font(.ui(12))
                        .foregroundColor(Palette.inkSecondary)
                }
            } else {
                ModelStateBadge.ready
            }
        } else {
            ModelStateBadge.download(size: model.size)
        }
    }

    /// Controls that are NOT the selection: they sit outside the row button so
    /// downloading or opening the menu never switches the active model.
    private var trailingControls: some View {
        HStack(spacing: 8) {
            if !isDownloaded {
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
            HStack(alignment: .top, spacing: 12) {
                Button(action: setDefaultAction) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(model.displayName)
                                    .font(.ui(13, weight: .semibold))
                                    .foregroundColor(Palette.inkPrimary)
                                if isCurrent && isDownloaded {
                                    ModelStateBadge.active
                                }
                                Spacer()
                            }

                            Text("Imported local model")
                                .font(.ui(11))
                                .foregroundColor(Palette.inkSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if isDownloaded {
                            ModelStateBadge.ready
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .disabled(!isDownloaded)
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])

                HStack(spacing: 8) {
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
            .font(.ui(11))
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
        case active
        case ready
        case download(size: String)
    }

    let kind: Kind

    static let selectedNotDownloaded = ModelStateBadge(kind: .selectedNotDownloaded)
    static let active = ModelStateBadge(kind: .active)
    static let ready = ModelStateBadge(kind: .ready)
    static func download(size: String) -> ModelStateBadge { ModelStateBadge(kind: .download(size: size)) }

    var body: some View {
        switch kind {
        case .selectedNotDownloaded:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text("Selected · not downloaded")
                    .font(.ui(11, weight: .medium))
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
        case .active:
            Text("ACTIVE")
                .font(.microlabel(10))
                .tracking(0.18 * 10)
                .foregroundColor(Palette.phosphor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Palette.phosphor.opacity(0.12))
                )
                .accessibilityLabel("Active model")
        case .ready:
            Text("READY")
                .font(.microlabel(10))
                .tracking(0.18 * 10)
                .foregroundColor(Palette.inkSecondary)
                .fixedSize()
        case .download(let size):
            Text("\(size.uppercased()) DOWNLOAD")
                .font(.microlabel(10))
                .tracking(0.18 * 10)
                .foregroundColor(Palette.inkSecondary)
                .fixedSize()
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
