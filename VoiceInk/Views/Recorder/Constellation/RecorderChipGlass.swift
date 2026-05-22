import SwiftUI

// MARK: - ClusterPhase → HaloPhase

extension HaloPhase {
    /// Maps the cluster-side `ClusterPhase` to the view-side `HaloPhase` that
    /// drives `recorderChip` glass + halo color. The chip cluster never enters
    /// `.armed` or `.liveText`, so those `HaloPhase` cases are unreachable here.
    init(clusterPhase: ClusterPhase) {
        switch clusterPhase {
        case .idle:         self = .hidden
        case .recording:    self = .recording
        case .transcribing: self = .transcribing
        case .enhancing:    self = .enhancing
        case .done:         self = .done
        case .failed:       self = .failed
        }
    }
}

// MARK: - RecorderChipGlass
//
// Onyx tactical-glass background for the floating-recorder cluster chips —
// the Constellation equivalent of Bay's capsule material. Built on
// `TacticalGlass` / `HaloMaterial` (the app-wide onyx glass), NOT the shared
// flat `GlassChip` primitive — so the recorder carries phase-keyed halos
// without restyling the Settings / History / Metrics chips that also use
// `GlassChip`.
//
// `phase` drives the outer halo: pass the cluster's live `HaloPhase` for the
// anchor chip (it glows), `.hidden` for secondary / action chips (onyx glass,
// no glow). On `.enhancing` the modifier drives `HaloMaterial`'s breathePulse
// so the anchor's violet halo breathes — replacing the retired `ChipBreath`.

struct RecorderChipGlass: ViewModifier {
    let phase: HaloPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breatheUp = false

    private static let cornerRadius: CGFloat = 10
    private static let paddingH: CGFloat = 11
    private static let paddingV: CGFloat = 7

    func body(content: Content) -> some View {
        let isEnhancing = (phase == .enhancing)
        let pulse: Double = {
            guard isEnhancing else { return 0 }
            if reduceMotion { return 0.5 }      // static mid-amplitude
            return breatheUp ? 1.0 : 0.0
        }()

        content
            .padding(.horizontal, Self.paddingH)
            .padding(.vertical, Self.paddingV)
            .background(
                TacticalGlass<RoundedRectangle>(
                    shape: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous),
                    phase: phase,
                    breathePulse: pulse,
                    showInnerSheen: isEnhancing
                )
            )
            .onAppear { startBreathe() }
            .onChange(of: reduceMotion) { _, _ in startBreathe() }
    }

    /// Drives the repeating breathe for the enhancing anchor. Resets to rest
    /// for every other phase and under Reduce Motion.
    private func startBreathe() {
        guard phase == .enhancing, !reduceMotion else {
            breatheUp = false
            return
        }
        breatheUp = false
        withAnimation(.chipBreath) { breatheUp = true }
    }
}

extension View {
    /// Wraps a floating-recorder cluster chip in onyx tactical glass.
    /// Pass the cluster's live `HaloPhase` for the anchor chip; `.hidden`
    /// for secondary / action chips.
    func recorderChip(phase: HaloPhase) -> some View {
        modifier(RecorderChipGlass(phase: phase))
    }
}
