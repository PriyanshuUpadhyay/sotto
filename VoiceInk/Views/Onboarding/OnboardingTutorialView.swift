import SwiftUI

// MARK: - OnboardingTutorialView (P2.G)
//
// Final onboarding step — replays the P2.F `CinematicWalkthrough` as the
// "tutorial recap" the user signed off on (acceptance criteria, plan §P2.G).
// The cinematic plays auto-magically; once it ends, a Replay chip appears at
// the top-right of the embedded card so the user can re-watch on demand.
//
// The previous TextEditor/"Try It Out!" testbed was retired here — verifying
// the real recorder is now the user's first action after `Complete Setup`,
// inside the actual app surface (not a contrived onboarding sandbox). The
// menu bar icon + Help → Show Tutorial keep the cinematic discoverable.

struct OnboardingTutorialView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var walkthroughDone = false
    @State private var replayKey: Int = 0
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared

    private static let cardWidth: CGFloat = 720
    private static let cardHeight: CGFloat = 360

    var body: some View {
        ZStack {
            OnboardingBackgroundView().ignoresSafeArea()

            VStack(spacing: 28) {
                header
                cinematicHost
                actionRow
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Recap")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.55))

            Text("Here's how it'll feel")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Press your shortcut anywhere on macOS — VoiceInk listens, transcribes, and pastes.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
    }

    // MARK: - Cinematic host (embedded, not full-screen)

    private var cinematicHost: some View {
        ZStack(alignment: .topTrailing) {
            CinematicWalkthrough(onFinish: {
                withAnimation(motion.reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    walkthroughDone = true
                }
            })
            .id(replayKey)
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 10)

            if walkthroughDone {
                replayChip
                    .padding(16)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    private var replayChip: some View {
        Button {
            withAnimation(motion.reduceMotion ? nil : .easeOut(duration: 0.18)) {
                walkthroughDone = false
            }
            replayKey &+= 1
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                Text("Replay")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Replay walkthrough")
    }

    // MARK: - Action row

    private var actionRow: some View {
        VStack(spacing: 12) {
            Button {
                hasCompletedOnboarding = true
            } label: {
                Text("Complete Setup")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 220, height: 46)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(ScaleButtonStyle())

            SkipButton(text: "Replay later from Help → Show Tutorial") {
                hasCompletedOnboarding = true
            }
        }
    }
}
