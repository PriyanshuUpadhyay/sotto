import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case permissions
    case hotkey
    case done

    var id: Int { rawValue }

    func next() -> OnboardingStep {
        OnboardingStep(rawValue: rawValue + 1) ?? .done
    }

    func previous() -> OnboardingStep {
        OnboardingStep(rawValue: rawValue - 1) ?? .welcome
    }
}
