import Testing
import Foundation
import SwiftData
@testable import Sotto

@Suite struct EnhancementEditRecordTests {
    private func container() -> ModelContainer {
        let schema = Schema([EnhancementEditRecord.self])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [cfg])
    }

    @Test("inserts and reads back a record with all fields")
    func roundTrip() throws {
        let ctx = ModelContext(container())
        let rec = EnhancementEditRecord(
            rawText: "raw", enhancedText: "enh", finalText: "final",
            appBundleID: "com.x", transcriptionID: UUID(),
            enhancedHash: "h", editKind: .style
        )
        ctx.insert(rec)
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<EnhancementEditRecord>())
        #expect(all.count == 1)
        #expect(all[0].editKindRaw == "style")
        #expect(all[0].analyzed == false)
    }

    @Test("EditSignalSource has the three explicit signals with stable raw values")
    func signalSourceRawValues() {
        #expect(EditSignalSource.revertRaw.rawValue == "revertRaw")
        #expect(EditSignalSource.thumbsDown.rawValue == "thumbsDown")
        #expect(EditSignalSource.edit.rawValue == "edit")
        #expect(EditSignalSource(rawValue: "edit") == .edit)
    }

    @Test("record persists signalSource; default is edit")
    func signalSourceRoundTrip() throws {
        let ctx = ModelContext(container())
        let rec = EnhancementEditRecord(
            rawText: "raw", enhancedText: "enh", finalText: "raw",
            appBundleID: "com.x", transcriptionID: UUID(),
            enhancedHash: "h", editKind: .style,
            signalSource: .revertRaw)
        ctx.insert(rec)
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<EnhancementEditRecord>())
        #expect(all.count == 1)
        #expect(all[0].signalSource == .revertRaw)
        #expect(all[0].signalSourceRaw == "revertRaw")
        let bare = EnhancementEditRecord(
            rawText: "r", enhancedText: "e", finalText: "f",
            appBundleID: nil, transcriptionID: UUID(),
            enhancedHash: "h", editKind: .style)
        #expect(bare.signalSource == .edit)
    }
}
