import SwiftUI

// MARK: - OnboardingModelDownloadView (P2.G)
//
// Glass-card model picker. The recommended Whisper turbo model is the only
// curated option here (per existing v1 product behavior — full picker lives
// in Settings → AI Models). Card swaps from a "Download Model" CTA to a
// horizontal glass progress bar during download, then to a "Set as Default"
// / "Continue" terminal state once the model is downloaded + selected.
//
// Reviewer focus (plan §P2.G): models actually download. The download / set-
// as-default / advance-to-tutorial logic is preserved verbatim from v1; only
// the layout shell changed (Form/Vstack chrome → GlassCard).

struct OnboardingModelDownloadView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var isDownloading = false
    @State private var isModelSet = false
    @State private var showTutorial = false
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared

    private let turboModel = TranscriptionModelRegistry.models.first { $0.name == "ggml-large-v3-turbo-q5_0" } as! WhisperModel

    var body: some View {
        ZStack {
            if showTutorial {
                OnboardingTutorialView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ZStack {
                    OnboardingBackgroundView().ignoresSafeArea()

                    VStack(spacing: 28) {
                        header
                        modelCard
                        actionRow
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 40)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear { checkModelStatus() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Model")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.55))

            Text("Download AI Model")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("VoiceInk uses Whisper Large v3 Turbo — fast, accurate, on-device.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
    }

    // MARK: - Model card

    private var modelCard: some View {
        GlassCard(cornerRadius: 18, padding: 20, appearance: .onyx) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    iconTile

                    VStack(alignment: .leading, spacing: 4) {
                        Text(turboModel.displayName)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("\(turboModel.size) · \(turboModel.language)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Spacer(minLength: 8)

                    statusPill
                }

                Divider().opacity(0.25)

                // Performance metrics row.
                HStack(spacing: 24) {
                    metric(label: "Speed", value: turboModel.speed, tint: Palette.transcribe)
                    metric(label: "Accuracy", value: turboModel.accuracy, tint: Palette.success)
                    ramMetric(gb: turboModel.ramUsage)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isDownloading {
                    glassProgressBar
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Palette.enhance.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.enhance.opacity(0.32), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: isModelSet ? "checkmark.seal.fill" : "brain.head.profile")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isModelSet ? Palette.success : Palette.enhance)
            )
            .frame(width: 44, height: 44)
    }

    private var statusPill: some View {
        let granted = isModelSet
        let tone: Color = granted ? Palette.success : Palette.warn
        let label: String = granted
            ? "READY"
            : (isDownloading ? "DOWNLOADING" : "PENDING")
        return Text(label)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.6)
            .foregroundColor(tone)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tone.opacity(0.14)))
            .overlay(Capsule().stroke(tone.opacity(0.36), lineWidth: 0.5))
    }

    // MARK: - Glass progress bar (replaces v1 stock DownloadProgressView)

    private var glassProgressBar: some View {
        let progress = totalProgress
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(downloadPhase)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track — translucent glass channel.
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                        )

                    // Fill — enhance-tinted with a subtle gloss.
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Palette.enhance,
                                    Palette.enhance.opacity(0.85)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geometry.size.width * progress))
                        .shadow(color: Palette.enhance.opacity(0.45), radius: 6, x: 0, y: 0)
                        .animation(motion.reduceMotion ? nil : .easeOut(duration: 0.2), value: progress)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement()
        .accessibilityLabel("Downloading \(turboModel.displayName), \(Int(progress * 100)) percent")
    }

    private var totalProgress: Double {
        let main = whisperModelManager.downloadProgress[turboModel.name + "_main"] ?? 0
        let supportsCoreML = !turboModel.name.contains("q5") && !turboModel.name.contains("q8")
        guard supportsCoreML else { return main }
        let coreML = whisperModelManager.downloadProgress[turboModel.name + "_coreml"] ?? 0
        return main * 0.5 + coreML * 0.5
    }

    private var downloadPhase: String {
        let supportsCoreML = !turboModel.name.contains("q5") && !turboModel.name.contains("q8")
        if supportsCoreML, whisperModelManager.downloadProgress[turboModel.name + "_coreml"] != nil {
            return "Downloading Core ML weights…"
        }
        return "Downloading model weights…"
    }

    // MARK: - Metrics

    private func metric(label: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundColor(.white.opacity(0.55))
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    Capsule()
                        .fill(Double(index) / 5.0 < value ? tint : Color.white.opacity(0.16))
                        .frame(width: 14, height: 4)
                }
            }
        }
    }

    private func ramMetric(gb: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RAM")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundColor(.white.opacity(0.55))
            Text(String(format: "%.1f GB", gb))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        VStack(spacing: 12) {
            Button(action: handleAction) {
                Text(getButtonTitle())
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 220, height: 46)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(isDownloading)
            .opacity(isDownloading ? 0.65 : 1.0)

            if !isModelSet {
                SkipButton(text: "Skip for now") {
                    withAnimation(.haloExpand) { showTutorial = true }
                }
            }
        }
    }

    // MARK: - Logic (verbatim from v1)

    private func checkModelStatus() {
        if whisperModelManager.availableModels.contains(where: { $0.name == turboModel.name }) {
            isModelSet = transcriptionModelManager.currentTranscriptionModel?.name == turboModel.name
        }
    }

    private func handleAction() {
        if isModelSet {
            withAnimation(.haloExpand) { showTutorial = true }
        } else if whisperModelManager.availableModels.contains(where: { $0.name == turboModel.name }) {
            if let modelToSet = transcriptionModelManager.allAvailableModels.first(where: { $0.name == turboModel.name }) {
                Task {
                    transcriptionModelManager.setDefaultTranscriptionModel(modelToSet)
                    withAnimation { isModelSet = true }
                }
            }
        } else {
            withAnimation { isDownloading = true }
            Task {
                await whisperModelManager.downloadModel(turboModel)
                if let modelToSet = transcriptionModelManager.allAvailableModels.first(where: { $0.name == turboModel.name }) {
                    transcriptionModelManager.setDefaultTranscriptionModel(modelToSet)
                    withAnimation {
                        isModelSet = true
                        isDownloading = false
                    }
                }
            }
        }
    }

    private func getButtonTitle() -> String {
        if isModelSet { return "Continue" }
        if isDownloading { return "Downloading…" }
        if whisperModelManager.availableModels.contains(where: { $0.name == turboModel.name }) {
            return "Set as Default"
        }
        return "Download Model"
    }
}
