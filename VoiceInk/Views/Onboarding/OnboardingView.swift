import SwiftUI

// MARK: - OnboardingView (P2.G)
//
// First-launch host. Plays the P2.F `CinematicWalkthrough` first, then drops
// to a glass-card welcome with `Get Started` → permissions → model download →
// tutorial recap (acceptance criteria, plan §P2.G).
//
// `walkthroughDone` is the only first-launch gate — once the cinematic ends
// (or is skipped), the welcome card fades in. The previous typewriter intro
// was retired; `TypewriterRoles` and the legacy welcome scroll structure are
// replaced by the cinematic.

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var walkthroughDone = false
    @State private var welcomeVisible = false
    @State private var showPermissions = false
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared

    var body: some View {
        ZStack {
            // Reusable backdrop — kept identical across the four onboarding
            // surfaces so per-stage transitions read as a single environment.
            OnboardingBackgroundView()
                .ignoresSafeArea()

            // Welcome stage — cinematic first, glass CTA after.
            if !walkthroughDone {
                CinematicWalkthrough(onFinish: {
                    withAnimation(motion.reduceMotion ? nil : .easeOut(duration: 0.32)) {
                        walkthroughDone = true
                    }
                })
                .transition(.opacity)
            } else {
                welcomeCard
                    .opacity(welcomeVisible ? 1 : 0)
                    .scaleEffect(welcomeVisible ? 1.0 : 0.97)
                    .animation(
                        motion.reduceMotion ? nil : .haloExpand,
                        value: welcomeVisible
                    )
            }

            // Permissions overlay — slides in over the welcome card.
            if showPermissions {
                OnboardingPermissionsView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onChange(of: walkthroughDone) { _, done in
            guard done else { return }
            // Brief pause so the cinematic fade-out + welcome fade-in don't
            // step on each other visually.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                welcomeVisible = true
            }
        }
    }

    // MARK: - Welcome card

    private var welcomeCard: some View {
        GlassCard(cornerRadius: 22, padding: 32, appearance: .onyx) {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Text("Welcome to VoiceInk")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("A new way to type — speak, transcribe, enhance.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    Button {
                        withAnimation(motion.reduceMotion ? nil : .haloExpand) {
                            showPermissions = true
                        }
                    } label: {
                        Text("Get Started")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(width: 200, height: 46)
                            .background(Color.white)
                            .cornerRadius(23)
                    }
                    .buttonStyle(ScaleButtonStyle())

                    SkipButton(text: "Skip Tour") {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .frame(width: 460)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to VoiceInk. A new way to type.")
    }
}

// MARK: - Supporting Views (kept for cross-file reuse)

struct SkipButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(.white.opacity(0.5))
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(text)
    }
}

struct OnboardingBackgroundView: View {
    @State private var glowOpacity: CGFloat = 0
    @State private var glowScale: CGFloat = 0.8
    @State private var particlesActive = false
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.black,
                                Color.black.opacity(0.8),
                                Color.black.opacity(0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Ambient glow — frozen at mid-state under Reduce Motion.
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: min(geometry.size.width, geometry.size.height) * 0.4)
                    .blur(radius: 100)
                    .opacity(motion.reduceMotion ? 0.15 : glowOpacity)
                    .scaleEffect(motion.reduceMotion ? 1.0 : glowScale)
                    .position(
                        x: geometry.size.width * 0.5,
                        y: geometry.size.height * 0.3
                    )

                // Particles disabled under Reduce Motion (spec §6.4).
                if !motion.reduceMotion {
                    ParticlesView(isActive: $particlesActive)
                        .opacity(0.18)
                        .drawingGroup()
                }
            }
        }
        .onAppear { startAnimations() }
    }

    private func startAnimations() {
        guard !motion.reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowOpacity = 0.3
            glowScale = 1.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            particlesActive = true
        }
    }
}

// MARK: - Particles
struct ParticlesView: View {
    @Binding var isActive: Bool
    let particleCount = 60

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let timeOffset = timeline.date.timeIntervalSinceReferenceDate

                for i in 0..<particleCount {
                    let position = particlePosition(index: i, time: timeOffset, size: size)
                    let opacity = particleOpacity(index: i, time: timeOffset)
                    let scale = particleScale(index: i, time: timeOffset)

                    context.opacity = opacity
                    context.fill(
                        Circle().path(in: CGRect(
                            x: position.x - scale/2,
                            y: position.y - scale/2,
                            width: scale,
                            height: scale
                        )),
                        with: .color(.white)
                    )
                }
            }
        }
        .opacity(isActive ? 1 : 0)
    }

    private func particlePosition(index: Int, time: TimeInterval, size: CGSize) -> CGPoint {
        let relativeIndex = Double(index) / Double(particleCount)
        let speed = 0.3
        let radius = min(size.width, size.height) * 0.45

        let angle = time * speed + relativeIndex * .pi * 4
        let x = sin(angle) * radius + size.width * 0.5
        let y = cos(angle * 0.5) * radius + size.height * 0.5

        return CGPoint(x: x, y: y)
    }

    private func particleOpacity(index: Int, time: TimeInterval) -> Double {
        let relativeIndex = Double(index) / Double(particleCount)
        return (sin(time + relativeIndex * .pi * 2) + 1) * 0.3
    }

    private func particleScale(index: Int, time: TimeInterval) -> CGFloat {
        let relativeIndex = Double(index) / Double(particleCount)
        let baseScale: CGFloat = 3
        return baseScale + sin(time * 2 + relativeIndex * .pi) * 2
    }
}

// MARK: - Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview
#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .frame(width: 950, height: 730)
}
