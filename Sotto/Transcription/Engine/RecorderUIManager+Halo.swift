import Foundation
import SwiftUI
import Combine
import os

extension RecorderUIManager {
    // MARK: - Halo phase mapping

    func setupPhaseObservers(engine: SottoEngine, registry: FailureRegistry) {
        engine.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.mapEngineState(state, engine: engine)
            }
            .store(in: &phaseObservers)

        // The `.armed → .recording` gate (first audio + arming hold) only
        // becomes satisfiable *after* the engine's single `.recording` state
        // publish, so re-evaluate it each time the first-audio gate latches.
        engine.firstAudioGate.$observed
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak engine] _ in
                guard let self, let engine else { return }
                self.evaluateRecordingPhase(engine: engine)
            }
            .store(in: &phaseObservers)

        registry.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                if let event {
                    self.currentErrorCode = Self.errorCode(from: event)
                    self.phase = .failed
                } else if self.phase == .failed {
                    self.phase = .hidden
                    self.currentErrorCode = nil
                }
            }
            .store(in: &phaseObservers)

        engine.$lastPasteEvent
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.beginDoneHold(appName: event.appName)
                // Float the independent post-paste tray over the lingering
                // capsule — but ONLY when review-before-paste is off. In review
                // mode the user already reviewed/edited in the compose editor
                // before this paste, so a second box would be redundant.
                let reviewOn = UserDefaults.standard.object(forKey: "ReviewBeforePaste") as? Bool ?? true
                if !reviewOn {
                    self?.reviewTrayWindowManager.present(event)
                }
            }
            .store(in: &phaseObservers)

        $phase
            .removeDuplicates()
            .sink { [weak self] new in
                self?.logger.notice("phase → \(String(describing: new), privacy: .public)")
            }
            .store(in: &phaseObservers)

        $phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] new in
                let interactive = Self.isInteractive(new)
                self?.miniWindowManager?.setIgnoresMouseEvents(!interactive)
            }
            .store(in: &phaseObservers)
    }

    /// Phases whose chips carry tappable controls (RETRY / OPEN SETTINGS) or
    /// otherwise warrant hit-testing. Outside these the panel stays
    /// click-through so menu-bar / app clicks fall through the full-width strip.
    /// `.recording` / `.liveText` / `.done` render no control — the post-paste
    /// actions live on the independent `ReviewTrayWindowManager` panel — so the
    /// strip must not opt a screen-wide region into hit testing for them.
    nonisolated static func isInteractive(_ phase: HaloPhase) -> Bool {
        phase == .failed
    }

    private func mapEngineState(_ state: RecordingState, engine: SottoEngine) {
        if state == .starting && phase == .done {
            doneHoldTask?.cancel()
            // A new recording supersedes the review window: the panel is already
            // on screen, so re-arming continues showing it (no hide/flash).
            isReviewWindowActive = false
            phase = .hidden
            lastPasteAppName = nil
        }

        if phase == .done || phase == .failed { return }

        switch state {
        case .idle, .busy:
            armingHoldTask?.cancel()
            phase = .hidden
            recordingStartedAt = nil
        case .starting:
            phase = .armed
            if recordingStartedAt == nil { recordingStartedAt = .now }
        case .recording:
            if recordingStartedAt == nil { recordingStartedAt = .now }
            phase = .armed
            evaluateRecordingPhase(engine: engine)
        case .transcribing:
            phase = .transcribing
        case .enhancing:
            phase = .enhancing
        }

        formattedActivePromptLabel = engine.enhancementService?.isEnhancementEnabled == true
            ? Self.formatPromptLabel(PredefinedPrompts.defaultPrompt.title)
            : nil
    }

    /// Re-evaluates the `.armed → .recording` promotion. Both gate conditions
    /// — first audio observed (`FirstAudioGate`, spec §4.2) and the
    /// `MotionTokens.armingHold` dwell — typically become true *after* the
    /// engine's lone `.recording` state publish, so this runs from the
    /// `firstAudioGate.$observed` observer and a follow-up timer, not only
    /// from `mapEngineState`. Idempotent — safe to call spuriously.
    private func evaluateRecordingPhase(engine: SottoEngine) {
        guard engine.recordingState == .recording, phase == .armed,
              engine.firstAudioObserved,
              let started = recordingStartedAt else { return }

        armingHoldTask?.cancel()
        let elapsed = Date().timeIntervalSince(started)
        if elapsed >= MotionTokens.armingHold {
            phase = .recording
        } else {
            // First audio beat the arming hold — wait out the remainder.
            armingHoldTask = Task { @MainActor [weak self, weak engine] in
                try? await Task.sleep(for: .seconds(MotionTokens.armingHold - elapsed))
                guard !Task.isCancelled, let self, let engine else { return }
                self.evaluateRecordingPhase(engine: engine)
            }
        }
    }

    func beginDoneHold(appName: String?) {
        // A live dictation owns the panel — ignore paste events and fallback holds while starting or recording.
        if engine?.recordingState == .starting || engine?.recordingState == .recording {
            return
        }

        doneHoldTask?.cancel()
        lastPasteAppName = appName
        phase = .done
        // When the panel is being kept up for the post-paste ReviewTray, hold
        // for the (longer) review window so the tray is usable; otherwise the
        // brief committed dwell.
        let hold = isReviewWindowActive ? MotionTokens.reviewWindowHold : MotionTokens.committedHold
        doneHoldTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled, let self else { return }
            if self.phase == .done {
                self.phase = .hidden
                self.lastPasteAppName = nil
                // Review window elapsed without a superseding recording — tear
                // the panel down now (`isMiniRecorderVisible` is already false).
                if self.isReviewWindowActive {
                    self.isReviewWindowActive = false
                    self.hideRecorderPanel()
                }
            }
        }
    }

    private static func formatPromptLabel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let upper = raw.uppercased()
        if upper.count <= 9 { return upper }
        let idx = upper.index(upper.startIndex, offsetBy: 9)
        return String(upper[..<idx])
    }

    /// Terse cause shown in place of "failed" on the fail capsule, plus
    /// whether retrying can help: without a model, a retry fails identically,
    /// so that case must offer Settings instead of ⌘R.
    enum FailureCode: String {
        case noModel  = "ERR · NO_MODEL"
        case noDevice = "ERR · NO_DEVICE"
        case network  = "ERR · NETWORK"
        case noAudio  = "ERR · NO_AUDIO"
        case unknown  = "ERR · UNKNOWN"

        var isRetryable: Bool { self != .noModel }
    }

    static func errorCode(from event: FailureEvent) -> FailureCode {
        let r = event.reason.uppercased()
        if r.contains("MODEL")          { return .noModel }
        if r.contains("DEVICE") || r.contains("MIC") { return .noDevice }
        if r.contains("NETWORK")        { return .network }
        if r.contains("AUDIO")          { return .noAudio }
        return .unknown
    }

    func dismissFailedPhase() {
        guard phase == .failed else { return }
        failureRegistry?.acknowledgeCurrent()
    }

    /// ESC #2 — end the post-paste review window NOW (the tray is already
    /// closed): cancel the done-hold, drop the review flag, and tear the
    /// lingering capsule/HUD down immediately. No-op outside the review window.
    func endReviewWindowNow() {
        guard isReviewWindowActive else { return }
        doneHoldTask?.cancel()
        isReviewWindowActive = false
        if phase == .done { phase = .hidden }
        lastPasteAppName = nil
        hideRecorderPanel()
    }
}
