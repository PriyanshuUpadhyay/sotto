import Foundation
import KeyboardShortcuts
import AppKit
import Combine

extension KeyboardShortcuts.Name {
    static let escapeRecorder = Self("escapeRecorder")
    static let retryRecorder = Self("retryRecorder")
    static let cancelRecorder = Self("cancelRecorder")
    static let toggleEnhancement = Self("toggleEnhancement", default: .init(.e, modifiers: .command))
}

@MainActor
class MiniRecorderShortcutManager: ObservableObject {
    private var engine: SottoEngine
    private var recorderUIManager: RecorderUIManager
    private var visibilityTask: Task<Void, Never>?
    private var escapeActivationTask: Task<Void, Never>?
    private var retryActivationTask: Task<Void, Never>?
    
    private var isCancelHandlerSetup = false
    
    private var isEscapeHandlerSetup = false

    private var isRetryHandlerSetup = false
    
    init(engine: SottoEngine, recorderUIManager: RecorderUIManager) {
        self.engine = engine
        self.recorderUIManager = recorderUIManager
        // Clear any persisted .escapeRecorder before the visibility observer mounts;
        // shared UserDefaults can carry an orphan registration from a duplicate
        // instance and intercept system-wide ESC until the observer first fires.
        KeyboardShortcuts.setShortcut(nil, for: .escapeRecorder)
        // Same reasoning for ⌘R: it must exist ONLY while a retryable failure
        // capsule is on screen, never as a persisted global that shadows
        // Reload in the frontmost app.
        KeyboardShortcuts.setShortcut(nil, for: .retryRecorder)
        setupVisibilityObserver()
        setupEnhancementShortcut()
        setupEscapeHandlerOnce()
        setupCancelHandlerOnce()
        setupRetryHandlerOnce()
    }

    private func setupVisibilityObserver() {
        // Prompt / enhancement shortcuts stay tied to the LIVE session
        // (recorder visible).
        visibilityTask = Task { @MainActor in
            for await isVisible in recorderUIManager.$isMiniRecorderVisible.values {
                if isVisible {
                    KeyboardShortcuts.enable(.toggleEnhancement)
                    activateCancelShortcut()
                } else {
                    KeyboardShortcuts.disable(.toggleEnhancement)
                    deactivateCancelShortcut()
                }
            }
        }

        // ESC must stay active across BOTH the live session AND the post-paste
        // review window (the lingering capsule + the floating tray), since
        // `isMiniRecorderVisible` is false during review. Activate ESC whenever
        // any of: a live session, the review window, or the tray is up.
        escapeActivationTask = Task { @MainActor in
            let merged = Publishers.CombineLatest3(
                recorderUIManager.$isMiniRecorderVisible,
                recorderUIManager.$isReviewWindowActive,
                recorderUIManager.reviewTrayWindowManager.$isPresented
            )
            .map { $0 || $1 || $2 }
            .removeDuplicates()

            for await active in merged.values {
                if active { activateEscapeShortcut() } else { deactivateEscapeShortcut() }
            }
        }

        // ⌘R is bound ONLY while the fail capsule offers it — the `.failed`
        // phase with a retryable cause. `ERR · NO_MODEL` shows a Settings chip
        // instead, so ⌘R must not be live there either.
        retryActivationTask = Task { @MainActor in
            let retryable = Publishers.CombineLatest(
                recorderUIManager.$phase,
                recorderUIManager.$currentErrorCode
            )
            .map { phase, code in phase == .failed && (code?.isRetryable ?? true) }
            .removeDuplicates()

            for await active in retryable.values {
                if active {
                    KeyboardShortcuts.setShortcut(.init(.r, modifiers: .command), for: .retryRecorder)
                } else {
                    KeyboardShortcuts.setShortcut(nil, for: .retryRecorder)
                }
            }
        }
    }

    // Setup retry handler once
    private func setupRetryHandlerOnce() {
        guard !isRetryHandlerSetup else { return }
        isRetryHandlerSetup = true

        KeyboardShortcuts.onKeyDown(for: .retryRecorder) { [weak self] in
            Task { @MainActor in
                guard let self, self.recorderUIManager.phase == .failed else { return }
                // Same two steps as the chip: acknowledge the surfaced failure,
                // then re-arm through the engine retry path.
                self.recorderUIManager.dismissFailedPhase()
                NotificationCenter.default.post(name: .retryRecording, object: nil)
            }
        }
    }
    
    // Setup escape handler once
    private func setupEscapeHandlerOnce() {
        guard !isEscapeHandlerSetup else { return }
        isEscapeHandlerSetup = true
        
        KeyboardShortcuts.onKeyDown(for: .escapeRecorder) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }

                // Don't process if custom shortcut is configured
                guard KeyboardShortcuts.getShortcut(for: .cancelRecorder) == nil else { return }

                let ui = self.recorderUIManager
                let tray = ui.reviewTrayWindowManager

                // When the user has clicked into the tray (editing / buttons),
                // the panel is key and handles ESC LOCALLY (cancel edit, then
                // close) — don't double-fire from this global hook.
                if tray.isPanelKey { return }

                if ui.isMiniRecorderVisible {
                    // Live session — single press cancels (no two-tap dance).
                    await ui.cancelRecording()
                } else if tray.isPresented {
                    // ESC #1 — close the floating review tray.
                    tray.dismiss()
                } else if ui.isReviewWindowActive {
                    // ESC #2 — close the lingering recorder capsule/HUD.
                    ui.endReviewWindowNow()
                }
            }
        }
    }
    
    private func activateEscapeShortcut() {
        // Don't activate if custom shortcut is configured
        guard KeyboardShortcuts.getShortcut(for: .cancelRecorder) == nil else { return }
        KeyboardShortcuts.setShortcut(.init(.escape), for: .escapeRecorder)
    }
    
    // Setup cancel handler once
    private func setupCancelHandlerOnce() {
        guard !isCancelHandlerSetup else { return }
        isCancelHandlerSetup = true
        
        KeyboardShortcuts.onKeyDown(for: .cancelRecorder) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.recorderUIManager.isMiniRecorderVisible,
                      KeyboardShortcuts.getShortcut(for: .cancelRecorder) != nil else { return }

                await self.recorderUIManager.cancelRecording()
            }
        }
    }
    
    private func activateCancelShortcut() {
        // Handler checks if shortcut exists
    }
    
    private func deactivateEscapeShortcut() {
        KeyboardShortcuts.setShortcut(nil, for: .escapeRecorder)
    }
    
    private func deactivateCancelShortcut() {
        // Shortcut managed by user settings
    }
    
    private func setupEnhancementShortcut() {
        KeyboardShortcuts.onKeyDown(for: .toggleEnhancement) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.recorderUIManager.isMiniRecorderVisible,
                      let enhancementService = await self.engine.getEnhancementService() else { return }
                enhancementService.isEnhancementEnabled.toggle()
            }
        }

        // Don't capture the key globally until the mini recorder is visible.
        KeyboardShortcuts.disable(.toggleEnhancement)
    }

    deinit {
        visibilityTask?.cancel()
        escapeActivationTask?.cancel()
        retryActivationTask?.cancel()
        Task { @MainActor in
            KeyboardShortcuts.disable(.toggleEnhancement)
            deactivateEscapeShortcut()
            deactivateCancelShortcut()
            KeyboardShortcuts.setShortcut(nil, for: .retryRecorder)
        }
    }
}