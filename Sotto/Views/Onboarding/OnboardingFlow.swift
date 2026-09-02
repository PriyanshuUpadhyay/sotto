import SwiftUI
import AppKit

enum OnboardingFlowStep: Int, CaseIterable, Identifiable {
    case welcome
    case microphone
    case accessibility
    case screenRecording
    case shortcut
    case modelTier
    case done

    var id: Int { rawValue }

    var permissionStage: PermissionStage? {
        switch self {
        case .microphone: return .microphone
        case .accessibility: return .accessibility
        case .screenRecording: return .screenRecording
        default: return nil
        }
    }

    var isPermission: Bool { permissionStage != nil }

    var isRequired: Bool { permissionStage?.isRequired ?? false }

    var isOptional: Bool { isPermission && !isRequired }

    var isEssential: Bool {
        switch self {
        case .microphone, .shortcut, .modelTier, .done: return true
        case .welcome, .accessibility, .screenRecording: return false
        }
    }

    var requestsPermissionOnAppear: Bool { false }

    func canAdvance(granted: Bool) -> Bool {
        permissionStage?.canAdvance(granted: granted) ?? true
    }
}

enum OnboardingPath: CaseIterable {
    case full
    case essentials

    var steps: [OnboardingFlowStep] {
        switch self {
        case .full: return OnboardingFlowStep.allCases
        case .essentials: return OnboardingFlowStep.allCases.filter(\.isEssential)
        }
    }

    var firstStep: OnboardingFlowStep { steps.first ?? .done }

    func step(after step: OnboardingFlowStep) -> OnboardingFlowStep {
        let sequence = steps
        guard let index = sequence.firstIndex(of: step), index + 1 < sequence.count else {
            return .done
        }
        return sequence[index + 1]
    }

    func step(before step: OnboardingFlowStep) -> OnboardingFlowStep {
        let sequence = steps
        guard let index = sequence.firstIndex(of: step), index > 0 else { return firstStep }
        return sequence[index - 1]
    }

    /// Position of `step` in this path, and how many steps the path asks for.
    /// `.done` is the terminator, so it is not counted or numbered.
    func index(of step: OnboardingFlowStep) -> Int? {
        steps.firstIndex(of: step)
    }

    var visibleStepCount: Int { steps.filter { $0 != .done }.count }
}

struct OnboardingPosition: Equatable {
    var path: OnboardingPath
    var step: OnboardingFlowStep

    static let start = OnboardingPosition(path: .full, step: .welcome)

    var isFinished: Bool { step == .done }

    func skippingToEssentials() -> OnboardingPosition {
        OnboardingPosition(path: .essentials, step: OnboardingPath.essentials.firstStep)
    }

    func advanced() -> OnboardingPosition {
        OnboardingPosition(path: path, step: path.step(after: step))
    }

    func retreated() -> OnboardingPosition {
        OnboardingPosition(path: path, step: path.step(before: step))
    }

    /// 1-based number of the current step, or nil at `.done`.
    var stepNumber: Int? {
        guard step != .done, let index = path.index(of: step) else { return nil }
        return index + 1
    }

    var canRetreat: Bool { (path.index(of: step) ?? 0) > 0 && step != .done }
}

struct OnboardingFlow: View {
    let onFinish: () -> Void
    var requestPermission: ((PermissionStage) -> Void)?

    @State private var position: OnboardingPosition = .start
    @StateObject private var perms = PermissionManager()

    init(onFinish: @escaping () -> Void, requestPermission: ((PermissionStage) -> Void)? = nil) {
        self.onFinish = onFinish
        self.requestPermission = requestPermission
    }

    var body: some View {
        ZStack {
            OnboardingFlowBackdrop()

            stepContent
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                ZStack {
                    stepIndicator
                    HStack {
                        if position.canRetreat {
                            OnboardingFlowBackButton { position = position.retreated() }
                        }
                        Spacer()
                        OnboardingFlowSkipButton {
                            OnboardingState.shared.markSkipped()
                            onFinish()
                        }
                    }
                }
                Spacer()
            }
            .padding(16)
        }
        .frame(width: 480, height: 640)
    }

    /// Wayfinding: how far along the chosen path the user is. `.full` asks for
    /// six steps, `.essentials` three, so the count is read off the live path.
    @ViewBuilder
    private var stepIndicator: some View {
        if let number = position.stepNumber {
            Text("STEP \(number) OF \(position.path.visibleStepCount)")
                .font(.microlabel(11))
                .tracking(1.4)
                .foregroundColor(Palette.inkSecondary)
                .accessibilityLabel("Step \(number) of \(position.path.visibleStepCount)")
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch position.step {
        case .welcome:
            WelcomeStepView(
                onContinue: { advance() },
                onSkipToEssentials: { skipToEssentials() }
            )
        case .microphone, .accessibility, .screenRecording:
            if let stage = position.step.permissionStage {
                OnboardingPermissionStepView(
                    stage: stage,
                    perms: perms,
                    isGranted: granted(for: stage),
                    onRequest: { performRequest(stage) },
                    onAdvance: { advance() },
                    onSkip: { advance() }
                )
                .id(position.step)
            }
        case .shortcut:
            HotkeyStepView(onContinue: { advance() })
        case .modelTier:
            ModelTierStepView(onFinish: { advance() })
        case .done:
            Color.clear
        }
    }

    private func advance() {
        let next = position.advanced()
        if next.isFinished {
            finish()
        } else {
            position = next
        }
    }

    private func skipToEssentials() {
        position = position.skippingToEssentials()
    }

    private func finish() {
        OnboardingState.shared.markCompleted()
        onFinish()
    }

    private func granted(for stage: PermissionStage) -> Bool {
        switch stage {
        case .microphone: return perms.audioPermissionStatus == .authorized
        case .accessibility: return perms.isAccessibilityEnabled
        case .screenRecording: return perms.isScreenRecordingEnabled
        }
    }

    private func performRequest(_ stage: PermissionStage) {
        if let requestPermission {
            requestPermission(stage)
            return
        }
        switch stage {
        case .microphone:
            if perms.audioPermissionStatus == .notDetermined {
                perms.requestAudioPermission()
            } else {
                openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            }
        case .accessibility:
            openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording:
            perms.requestScreenRecordingPermission()
            openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }

    private func openSettings(_ raw: String) {
        if let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct OnboardingPermissionStepView: View {
    let stage: PermissionStage
    @ObservedObject var perms: PermissionManager
    let isGranted: Bool
    let onRequest: () -> Void
    let onAdvance: () -> Void
    let onSkip: () -> Void

    private var canAdvance: Bool {
        stage.canAdvance(granted: isGranted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PERMISSIONS")
                .font(.microlabel(11))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundColor(Palette.inkSecondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 30)

            Text(headline)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Palette.inkPrimary)

            Text(subtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 4)

            PermissionRow(
                icon: rowIcon,
                title: rowTitle,
                description: rowDescription,
                isGranted: isGranted,
                buttonTitle: rowButtonTitle,
                buttonAction: onRequest,
                checkPermission: { perms.checkAllPermissions() },
                infoTipMessage: rowInfoTip
            )

            Spacer()

            footer
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear { perms.checkAllPermissions() }
    }

    private var footer: some View {
        HStack {
            if !stage.isRequired {
                Button(action: onSkip) {
                    Text("Skip for now")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Palette.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Continues without granting this permission")
            }

            Spacer()

            Button(action: { if canAdvance { onAdvance() } }) {
                Text("Next")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 110)
            }
            .buttonStyle(OnboardingPhosphorButtonStyle(
                horizontalPadding: 20,
                verticalPadding: 10
            ))
            .opacity(canAdvance ? 1 : 0.4)
            .disabled(!canAdvance)
            .accessibilityHint(stage.isRequired && !isGranted ? "Grant microphone access to continue" : "")
        }
    }

    private var headline: String {
        switch stage {
        case .microphone: return "Allow microphone access"
        case .accessibility: return "Allow accessibility access"
        case .screenRecording: return "Allow screen recording"
        }
    }

    private var subtitle: String {
        switch stage {
        case .microphone:
            return "Required — Sotto records your voice to transcribe it. Dictation cannot start without it."
        case .accessibility:
            return "Recommended — lets Sotto paste transcribed text at your cursor in any app."
        case .screenRecording:
            return "Recommended — uses on-screen context to improve transcription accuracy."
        }
    }

    private var rowIcon: String {
        switch stage {
        case .microphone: return "mic"
        case .accessibility: return "hand.raised"
        case .screenRecording: return "rectangle.on.rectangle"
        }
    }

    private var rowTitle: String {
        switch stage {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }

    private var rowDescription: String {
        switch stage {
        case .microphone: return "Record your voice for transcription."
        case .accessibility: return "Paste transcribed text at your cursor across apps."
        case .screenRecording: return "Use screen context to improve accuracy."
        }
    }

    private var rowButtonTitle: String {
        switch stage {
        case .microphone:
            return perms.audioPermissionStatus == .notDetermined ? "Request Permission" : "Open System Settings"
        case .accessibility:
            return "Open System Settings"
        case .screenRecording:
            return "Request Permission"
        }
    }

    private var rowInfoTip: String? {
        switch stage {
        case .microphone:
            return nil
        case .accessibility:
            return "Sotto uses Accessibility to paste transcribed text directly at your cursor in any app."
        case .screenRecording:
            return "Sotto reads on-screen text to improve accuracy. It is processed locally and never stored."
        }
    }
}

private struct ModelTierStepView: View {
    let onFinish: () -> Void

    @State private var selected: TranscriptionTier = .balanced

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MODEL")
                .font(.microlabel(11))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundColor(Palette.inkSecondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 30)

            Text("Pick a transcription tier")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Palette.inkPrimary)

            Text("Higher tiers are more accurate; lower tiers are faster. All run on-device. Change it anytime in Settings ▸ Models.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 8)

            VStack(spacing: 10) {
                ForEach(TranscriptionTier.allCases) { tier in
                    tierRow(tier)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button(action: finish) {
                    Text("Finish")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(minWidth: 130)
                }
                .buttonStyle(OnboardingPhosphorButtonStyle(
                    horizontalPadding: 24,
                    verticalPadding: 11
                ))
                .accessibilityHint("Save the selected tier and finish setup")
                Spacer()
            }
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func tierRow(_ tier: TranscriptionTier) -> some View {
        let isSelected = tier == selected
        return Button(action: { selected = tier }) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? Palette.phosphor : Palette.inkTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Palette.inkPrimary)
                    Text(tier.subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(isSelected ? Palette.phosphor.opacity(0.12) : Palette.mtRaise)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(isSelected ? Palette.phosphor.opacity(0.55) : Palette.mtLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func finish() {
        UserDefaults.standard.set(selected.modelId, forKey: "CurrentTranscriptionModel")
        // Onboarding can't see the model managers; ask TranscriptionModelManager
        // to download (and then auto-activate) the picked tier's model. Finishing
        // is not blocked on the download — progress surfaces in Settings ▸ Models.
        NotificationCenter.default.post(
            name: .requestModelDownload,
            object: nil,
            userInfo: ["modelId": selected.modelId]
        )
        onFinish()
    }
}

/// Matte primary CTA — solid phosphor fill with an adaptive on-accent label,
/// the onboarding-scale equivalent of `phosphorPill()` (a rounded block instead
/// of a small capsule). The style owns foreground contrast in both appearances.
/// Shared across the onboarding
/// step views (`WelcomeStepView`, `HotkeyStepView`).
struct OnboardingPhosphorButtonStyle: ButtonStyle {
    var horizontalPadding: CGFloat = 24
    var verticalPadding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.phosphor)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct OnboardingFlowBackdrop: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            // Flat Graphite Matte setup surface. The window is an NSPanel with a
            // clear background (isOpaque=false), so this SwiftUI layer owns the
            // surface — `Palette.mtCanvas` is the furthest-back matte canvas, so
            // first-run matches the rest of the matte app. A single faint
            // phosphor wash keeps the Sotto personality; dropped under Increase
            // Contrast for a flat, maximally-legible panel.
            Palette.mtCanvas
            if contrast != .increased {
                RadialGradient(
                    colors: [Palette.phosphor.opacity(0.08), .clear],
                    center: UnitPoint(x: 0.5, y: 0.0),
                    startRadius: 0,
                    endRadius: 520
                )
            }
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingFlowBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text("Back")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(Palette.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .accessibilityHint("Returns to the previous setup step")
    }
}

private struct OnboardingFlowSkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Skip")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.inkTertiary)
                .padding(.horizontal, 10)
                .frame(height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip onboarding")
        .accessibilityHint("Skips setup and closes onboarding")
    }
}
