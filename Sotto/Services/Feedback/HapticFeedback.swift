import AppKit

// MARK: - FeedbackEvent
//
// The recorder lifecycle transitions that warrant tactile confirmation on a
// glance-free dictation tool. Earcons for these same moments already exist —
// they are owned by `SoundManager` (synthesized via `CueSynthesizer`) and fire
// at the same state-machine seams. `SottoFeedback` is the parallel HAPTIC
// channel: a progressive enhancement that only physically fires on Force Touch
// trackpads (Apple's performer is a silent no-op elsewhere).

enum FeedbackEvent {
    /// Recording armed/started. Co-located with `SoundManager.playStartSound`.
    case arm
    /// Transcript committed — pasted into the focused app. Co-located with the
    /// `PasteEvent` emission in `CursorPaster`.
    case commit
    /// A failure was surfaced. Co-located with `SoundManager.playFail`.
    case fail
}

// MARK: - SottoFeedback

/// Haptic feedback front-door. Mirrors the earcon seams in the recorder state
/// machine so sound + haptic land together on arm / commit / fail.
///
/// Haptics only physically fire on Force Touch trackpads — on other hardware
/// `NSHapticFeedbackPerformer.perform` is a no-op, so this stays a tasteful
/// progressive enhancement with no fallback noise.
@MainActor
enum SottoFeedback {

    /// `@AppStorage` key backing the user's haptics mute toggle
    /// (Settings → General → Recording Feedback). Default ON. Shared verbatim
    /// with `GeneralTab` so the toggle and this service read one source.
    static let hapticsEnabledKey = "feedbackHapticsEnabled"

    /// Whether haptics are enabled. Defaults to `true` when the key is unset.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: hapticsEnabledKey) as? Bool ?? true
    }

    /// Plays the haptic for `event`. No-op when the user has muted haptics.
    static func play(_ event: FeedbackEvent) {
        guard let pulses = resolvedPulses(for: event) else { return }
        perform(pulses)
    }

    // MARK: - Pure mapping (headlessly testable)

    /// Tactile pattern per event. `.fail` is a deliberate DOUBLE pulse so an
    /// error reads as distinct from the single-pulse arm / commit confirmations.
    static func pulses(for event: FeedbackEvent) -> [NSHapticFeedbackManager.FeedbackPattern] {
        switch event {
        case .arm:    return [.alignment]            // crisp "snapped into place" — armed
        case .commit: return [.levelChange]          // firmer detent — paste landed
        case .fail:   return [.generic, .generic]    // double tap — something went wrong
        }
    }

    /// The pulses that WOULD play given the current enabled state — `nil` when
    /// haptics are muted. Splitting the gate out keeps `play`'s decision pure
    /// and unit-testable without performing real haptics.
    static func resolvedPulses(for event: FeedbackEvent) -> [NSHapticFeedbackManager.FeedbackPattern]? {
        guard isEnabled else { return nil }
        return pulses(for: event)
    }

    // MARK: - Performer

    private static func perform(_ pulses: [NSHapticFeedbackManager.FeedbackPattern]) {
        guard let first = pulses.first else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(first, performanceTime: .now)

        // Subsequent pulses (the fail double-tap) are staggered so they read as
        // separate taps rather than one blurred buzz.
        for index in pulses.indices.dropFirst() {
            let pattern = pulses[index]
            let delaySeconds = Double(index) * 0.12
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
            }
        }
    }
}
