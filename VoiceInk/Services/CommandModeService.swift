import Foundation
import SwiftUI
import AppKit
import Combine
import os
import ApplicationServices

/// W12.B Command Mode — owns the global hotkey-driven highlight-and-rewrite
/// flow. The user presses Caps+9, the active selection is captured, the
/// recorder starts, the user dictates an instruction, and on stop the
/// transcribed instruction is applied to the captured selection by the active
/// enhance provider. The rewrite pastes at the cursor (replacing the
/// selection); the user's Cmd+Z restores the original.
///
/// Lifecycle:
///     idle → capturingSelection → recording → rewriting → pasting → idle
///
/// Owns:
///   - selection capture via `SelectedTextService.fetchSelectedText()`
///   - lifecycle state `phase` (drives recorder banner UI)
///   - `pendingCommand` handoff to `TranscriptionPipeline`
///   - rewrite invocation via `enhancementService.commandModeRewrite(...)`
///
/// See plan `docs/superpowers/plans/W12B-command-mode.md` §Migration policy
/// for the resolved design ambiguities.
@MainActor
final class CommandModeService: ObservableObject {
    static let shared = CommandModeService()

    enum Phase: Equatable {
        case idle
        case capturingSelection
        case recording
        case rewriting
        case pasting
    }

    struct PendingCommand: Equatable {
        let selectionText: String
        let capturedAt: Date
    }

    @Published private(set) var isActive: Bool = false
    @Published private(set) var phase: Phase = .idle
    /// Set in `start(...)` after a successful selection capture; consumed by
    /// `TranscriptionPipeline.run` to fork the post-transcribe routing. Cleared
    /// by `clear()` on success, abort, or cancel.
    private(set) var pendingCommand: PendingCommand?

    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "CommandModeService")

    /// Injected by the app root after services are wired. Held weakly so the
    /// service singleton doesn't capture a strong recorder UI reference.
    weak var recorderUIManager: RecorderUIManager?
    weak var enhancementService: AIEnhancementService?

    private init() {}

    func configure(recorderUIManager: RecorderUIManager, enhancementService: AIEnhancementService?) {
        self.recorderUIManager = recorderUIManager
        self.enhancementService = enhancementService
    }

    /// Invoked by the Caps+9 KeyboardShortcuts handler. Captures the active
    /// selection, sets `pendingCommand`, opens the recorder. Migration
    /// policies #6, #7, #13 govern the early-return paths.
    func start() async {
        // Migration policy #6 — re-pressing Caps+9 mid-dictation is a no-op.
        if let recorder = recorderUIManager, recorder.isMiniRecorderVisible {
            logger.notice("🦾 command-mode: ignored (recorder already visible)")
            return
        }
        // Migration policy #13 — AX-not-trusted graceful abort.
        guard AXIsProcessTrusted() else {
            logger.notice("🦾 command-mode: aborted (AX not trusted)")
            NotificationManager.shared.showNotification(
                title: "Grant Accessibility access to use Command Mode",
                type: .warning
            )
            return
        }

        phase = .capturingSelection
        isActive = true

        let selection = await SelectedTextService.fetchSelectedText()

        // Migration policy #7 — no selection → graceful abort with notification.
        guard let raw = selection,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.notice("🦾 command-mode: aborted (no selection)")
            NotificationManager.shared.showNotification(
                title: "No text selected. Highlight some text first.",
                type: .warning
            )
            isActive = false
            phase = .idle
            return
        }

        pendingCommand = PendingCommand(selectionText: raw, capturedAt: Date())
        logger.notice("🦾 command-mode: selection captured (\(raw.count, privacy: .public) chars), opening recorder")
        phase = .recording

        // Open the recorder. The user dictates; on stop the pipeline (via
        // T5's branch) calls `processInstruction(transcript:)` below.
        await recorderUIManager?.toggleMiniRecorder()
    }

    /// Invoked by `TranscriptionPipeline` after the transcript is produced
    /// and the pending command was non-nil. Returns the rewrite text. Throws
    /// if the rewrite fails — caller bypasses paste in that case (Migration
    /// policy #12).
    func processInstruction(transcript: String) async throws -> String {
        guard let pending = pendingCommand else {
            throw CommandModeError.noPendingCommand
        }
        guard let enhancementService else {
            throw CommandModeError.noEnhancementService
        }
        let instruction = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            throw CommandModeError.emptyInstruction
        }

        phase = .rewriting
        logger.notice("🦾 command-mode: rewriting (selection=\(pending.selectionText.count, privacy: .public) chars, instruction=\(instruction.count, privacy: .public) chars)")

        let (rewrite, _) = try await enhancementService.commandModeRewrite(
            selection: pending.selectionText,
            instruction: instruction
        )

        phase = .pasting
        return rewrite
    }

    /// Tear down command-mode state. Idempotent. Called from
    /// `TranscriptionPipeline` (after success or rewrite failure) and from
    /// `RecorderUIManager.dismissMiniRecorder()` (after cancel/Escape).
    func clear() {
        if isActive {
            logger.notice("🦾 command-mode: cleared (phase=\(String(describing: self.phase), privacy: .public))")
        }
        pendingCommand = nil
        isActive = false
        phase = .idle
    }
}

enum CommandModeError: LocalizedError {
    case noPendingCommand
    case noEnhancementService
    case emptyInstruction

    var errorDescription: String? {
        switch self {
        case .noPendingCommand:
            return "Command Mode internal state lost (no pending command)."
        case .noEnhancementService:
            return "AI enhancement service unavailable for Command Mode."
        case .emptyInstruction:
            return "No instruction was dictated."
        }
    }
}
