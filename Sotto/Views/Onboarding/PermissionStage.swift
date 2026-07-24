import Foundation

enum PermissionStage: Int, CaseIterable, Identifiable {
    case microphone
    case accessibility
    case screenRecording

    var id: Int { rawValue }

    var isRequired: Bool { self == .microphone }

    func next() -> PermissionStage? {
        PermissionStage(rawValue: rawValue + 1)
    }

    func canAdvance(granted: Bool) -> Bool {
        !isRequired || granted
    }
}
