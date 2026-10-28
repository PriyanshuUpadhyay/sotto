import Foundation
import SwiftUI

// MARK: - Download Progress View

struct DownloadProgressView: View {
    let modelName: String
    let downloadProgress: [String: Double]
    /// Whisper downloads in two phases keyed `_main` / `_coreml`; single-phase
    /// engines (FluidAudio) key their progress on the bare model name.
    var isTwoPhase: Bool = true
    var isPaused: Bool = false
    var onPause: (() -> Void)? = nil
    var onResume: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var mainProgress: Double {
        downloadProgress[isTwoPhase ? modelName + "_main" : modelName] ?? 0
    }

    private var coreMLProgress: Double {
        supportsCoreML ? (downloadProgress[modelName + "_coreml"] ?? 0) : 0
    }

    private var supportsCoreML: Bool {
        isTwoPhase && !modelName.contains("q5") && !modelName.contains("q8")
    }

    private var totalProgress: Double {
        supportsCoreML ? (mainProgress * 0.5) + (coreMLProgress * 0.5) : mainProgress
    }

    private var downloadPhase: String {
        if isPaused {
            return "Paused: \(modelName)"
        }
        if supportsCoreML && downloadProgress[modelName + "_coreml"] != nil {
            return "Downloading Core ML Model for \(modelName)"
        }
        return "Downloading \(modelName) Model"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(downloadPhase)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(.secondaryLabelColor))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Palette.hairlineSoft)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Palette.brandAcid)
                        .frame(width: max(0, min(geometry.size.width * totalProgress, geometry.size.width)), height: 6)
                }
            }
            .frame(height: 6)

            HStack(spacing: 8) {
                if let onPause, let onResume {
                    if isPaused {
                        Button("Resume", action: onResume)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    } else {
                        Button("Pause", action: onPause)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Spacer()
                Text(isPaused ? "Paused · \(Int(totalProgress * 100))%" : "\(Int(totalProgress * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(.secondaryLabelColor))
            }
        }
        .padding(.vertical, 4)
        .animation(.smooth, value: totalProgress)
    }
}
