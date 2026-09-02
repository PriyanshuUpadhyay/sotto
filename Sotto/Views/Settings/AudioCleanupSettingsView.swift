import SwiftUI
import SwiftData

struct AudioCleanupSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // Audio cleanup settings
    @AppStorage("IsTranscriptionCleanupEnabled") private var isTranscriptionCleanupEnabled = false
    @AppStorage("TranscriptionRetentionMinutes") private var transcriptionRetentionMinutes = 24 * 60
    @AppStorage("IsAudioCleanupEnabled") private var isAudioCleanupEnabled = false
    @AppStorage("AudioRetentionPeriod") private var audioRetentionPeriod = 7
    @State private var isPerformingCleanup = false
    @State private var isShowingConfirmation = false
    @State private var cleanupInfo: (fileCount: Int, totalSize: Int64, transcriptions: [Transcription]) = (0, 0, [])
    @State private var showResultAlert = false
    @State private var cleanupResult: (deletedCount: Int, errorCount: Int) = (0, 0)

    // Transcript cleanup — counted first, confirmed with the count, reported
    // with the count, exactly like the audio path below it.
    @State private var isCountingTranscripts = false
    @State private var transcriptCleanupCount = 0
    @State private var isShowingTranscriptConfirmation = false
    @State private var showTranscriptCleanupResult = false
    @State private var deletedTranscriptCount = 0

    // Expansion states - collapsed by default
    @State private var isTranscriptExpanded = false
    @State private var isAudioExpanded = false

    /// Shown on the audio row while transcript cleanup subsumes it.
    private static let audioSubsumedMessage =
        "Covered by Auto-delete Transcripts — deleting a transcript removes its audio."
    private static let audioMessage =
        "Automatically delete audio recordings while keeping text transcripts intact."

    var body: some View {
        Group {
            transcriptCleanupRow
            audioCleanupRow
        }
        .tint(Brand.tint)
    }

    // MARK: - Transcripts

    private var transcriptCleanupRow: some View {
        ExpandableSettingsRow(
            isExpanded: $isTranscriptExpanded,
            isEnabled: $isTranscriptionCleanupEnabled,
            label: "Auto-delete Transcripts",
            infoMessage: "Automatically delete transcript history based on the retention period you set."
        ) {
            Picker("Delete After", selection: $transcriptionRetentionMinutes) {
                Text("Immediately").tag(0)
                Text("1 hour").tag(60)
                Text("1 day").tag(24 * 60)
                Text("3 days").tag(3 * 24 * 60)
                Text("7 days").tag(7 * 24 * 60)
            }

            Button(isCountingTranscripts ? "Analyzing..." : "Run Cleanup Now") {
                Task {
                    await MainActor.run { isCountingTranscripts = true }
                    let count = await TranscriptionAutoCleanupService.shared
                        .countTranscriptionsToCleanup(modelContext: modelContext)
                    await MainActor.run {
                        transcriptCleanupCount = count
                        isCountingTranscripts = false
                        isShowingTranscriptConfirmation = true
                    }
                }
            }
            .disabled(isCountingTranscripts)
        }
        .onChange(of: isTranscriptionCleanupEnabled) { _, newValue in
            if newValue {
                AudioCleanupManager.shared.stopAutomaticCleanup()
            } else if isAudioCleanupEnabled {
                AudioCleanupManager.shared.startAutomaticCleanup(modelContext: modelContext)
            }
        }
        .alert("Transcript Cleanup", isPresented: $isShowingTranscriptConfirmation) {
            Button("Cancel", role: .cancel) { }

            if transcriptCleanupCount > 0 {
                Button("Delete \(transcriptCleanupCount) Transcripts", role: .destructive) {
                    Task {
                        let deleted = await TranscriptionAutoCleanupService.shared
                            .runManualCleanup(modelContext: modelContext)
                        await MainActor.run {
                            deletedTranscriptCount = deleted
                            showTranscriptCleanupResult = true
                        }
                    }
                }
            }
        } message: {
            if transcriptCleanupCount > 0 {
                Text("This will permanently delete \(transcriptCleanupCount) transcripts and their audio.")
            } else {
                Text("No transcripts are older than the retention period.")
            }
        }
        .alert("Cleanup Complete", isPresented: $showTranscriptCleanupResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Deleted \(deletedTranscriptCount) transcripts.")
        }
    }

    // MARK: - Audio files

    private var audioCleanupRow: some View {
        ExpandableSettingsRow(
            isExpanded: $isAudioExpanded,
            isEnabled: $isAudioCleanupEnabled,
            label: "Auto-delete Audio Files",
            infoMessage: isTranscriptionCleanupEnabled ? Self.audioSubsumedMessage : Self.audioMessage
        ) {
            Picker("Keep Audio For", selection: $audioRetentionPeriod) {
                Text("1 day").tag(1)
                Text("3 days").tag(3)
                Text("7 days").tag(7)
                Text("14 days").tag(14)
                Text("30 days").tag(30)
            }

            Button(isPerformingCleanup ? "Analyzing..." : "Run Cleanup Now") {
                Task {
                    await MainActor.run { isPerformingCleanup = true }
                    let info = await AudioCleanupManager.shared.getCleanupInfo(modelContext: modelContext)
                    await MainActor.run {
                        cleanupInfo = info
                        isPerformingCleanup = false
                        isShowingConfirmation = true
                    }
                }
            }
            .disabled(isPerformingCleanup)
        }
        // Subsumed, not hidden: transcript cleanup already deletes the audio,
        // so the row stays visible and explains why it is inert.
        .disabled(isTranscriptionCleanupEnabled)
        .alert("Audio Cleanup", isPresented: $isShowingConfirmation) {
            Button("Cancel", role: .cancel) { }

            if cleanupInfo.fileCount > 0 {
                Button("Delete \(cleanupInfo.fileCount) Files", role: .destructive) {
                    Task {
                        await MainActor.run { isPerformingCleanup = true }
                        let result = await AudioCleanupManager.shared.runCleanupForTranscriptions(
                            modelContext: modelContext,
                            transcriptions: cleanupInfo.transcriptions
                        )
                        await MainActor.run {
                            cleanupResult = result
                            isPerformingCleanup = false
                            showResultAlert = true
                        }
                    }
                }
            }
        } message: {
            if cleanupInfo.fileCount > 0 {
                Text("This will delete \(cleanupInfo.fileCount) audio files (\(AudioCleanupManager.shared.formatFileSize(cleanupInfo.totalSize))).")
            } else {
                Text("No audio files found older than \(audioRetentionPeriod) day\(audioRetentionPeriod > 1 ? "s" : "").")
            }
        }
        .alert("Cleanup Complete", isPresented: $showResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if cleanupResult.errorCount > 0 {
                Text("Deleted \(cleanupResult.deletedCount) files. Failed: \(cleanupResult.errorCount).")
            } else {
                Text("Deleted \(cleanupResult.deletedCount) audio files.")
            }
        }
    }
}
