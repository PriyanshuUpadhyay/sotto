import AppIntents
import Foundation
import AppKit

struct ToggleMiniRecorderIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Sotto Recorder"
    static var description = IntentDescription("Start or stop the Sotto mini recorder for voice transcription.")
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .toggleMiniRecorder, object: nil)
        
        let dialog = IntentDialog(stringLiteral: "Sotto recorder toggled")
        return .result(dialog: dialog)
    }
}

enum IntentError: Error, LocalizedError {
    case appNotAvailable
    case serviceNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .appNotAvailable:
            return "Sotto app is not available"
        case .serviceNotAvailable:
            return "Sotto recording service is not available"
        }
    }
}
