import Testing
import Foundation
import SwiftData
@testable import Sotto

@MainActor
@Suite(.serialized) struct FeedbackTrayToggleTests {
    private func service() -> AIEnhancementService {
        let schema = Schema([Transcription.self])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let ctx = ModelContext(try! ModelContainer(for: schema, configurations: [cfg]))
        return AIEnhancementService(modelContext: ctx)
    }

    @Test("showFeedbackTray defaults ON and writes through to UserDefaults")
    func toggleDefaultAndPersist() {
        UserDefaults.standard.removeObject(forKey: "ShowFeedbackTray")
        let svc = service()
        #expect(svc.showFeedbackTray == true)
        svc.showFeedbackTray = false
        #expect(UserDefaults.standard.bool(forKey: "ShowFeedbackTray") == false)
        UserDefaults.standard.removeObject(forKey: "ShowFeedbackTray")
    }
}
