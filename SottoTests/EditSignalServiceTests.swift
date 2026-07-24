import Testing
import Foundation
import SwiftData
@testable import Sotto

@Suite struct EditSignalServiceTests {
    private func ctx() -> ModelContext {
        let schema = Schema([EnhancementEditRecord.self])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try! ModelContainer(for: schema, configurations: [cfg]))
    }
    private func all(_ c: ModelContext) -> [EnhancementEditRecord] {
        (try? c.fetch(FetchDescriptor<EnhancementEditRecord>())) ?? []
    }
    private let svc = EditSignalService()
    private let tid = UUID()

    @Test(".revertRaw records finalText == rawText, source revertRaw")
    func revertRaw() {
        let c = ctx()
        svc.record(rawText: "raw text here", enhancedText: "Raw text, here.",
                   finalText: "ignored", source: .revertRaw,
                   appBundleID: "com.x", transcriptionID: tid, promptName: "Default", in: c)
        let r = all(c)
        #expect(r.count == 1)
        #expect(r[0].finalText == "raw text here")
        #expect(r[0].signalSource == .revertRaw)
    }

    @Test(".thumbsDown records finalText == enhancedText, source thumbsDown")
    func thumbsDown() {
        let c = ctx()
        svc.record(rawText: "raw", enhancedText: "the enhanced text",
                   finalText: "ignored", source: .thumbsDown,
                   appBundleID: nil, transcriptionID: tid, promptName: nil, in: c)
        let r = all(c)
        #expect(r.count == 1)
        #expect(r[0].finalText == "the enhanced text")
        #expect(r[0].signalSource == .thumbsDown)
    }

    @Test(".edit records the user-edited final text and classifies it")
    func edit() {
        let c = ctx()
        svc.record(rawText: "raw", enhancedText: "met with priyanshu today",
                   finalText: "met with Priyanshu today", source: .edit,
                   appBundleID: "com.y", transcriptionID: tid, promptName: nil, in: c)
        let r = all(c)
        #expect(r.count == 1)
        #expect(r[0].finalText == "met with Priyanshu today")
        #expect(r[0].signalSource == .edit)
        #expect(r[0].editKind == .spelling)
    }

    @Test(".edit no-op (final == enhanced normalized) records acceptedUnchanged")
    func editNoOpRecordsAcceptedUnchanged() {
        let c = ctx()
        svc.record(rawText: "raw", enhancedText: "the   enhanced text",
                   finalText: "the enhanced text", source: .edit,
                   appBundleID: nil, transcriptionID: tid, promptName: nil, in: c)
        let r = all(c)
        #expect(r.count == 1)
        #expect(r[0].signalSource == .acceptedUnchanged)
        #expect(r[0].finalText == "the   enhanced text")
    }

    @Test(".edit submitted empty coerces to thumbsDown, finalText == enhancedText")
    func editEmptyCoercesToThumbsDown() {
        let c = ctx()
        svc.record(rawText: "raw", enhancedText: "the enhanced text",
                   finalText: "   ", source: .edit,
                   appBundleID: nil, transcriptionID: tid, promptName: nil, in: c)
        let r = all(c)
        #expect(r.count == 1)
        #expect(r[0].signalSource == .thumbsDown)
        #expect(r[0].finalText == "the enhanced text")
    }

    @Test(".edit meaning-preserving rewrite still records as style")
    func editStyle() {
        let c = ctx()
        svc.record(rawText: "raw", enhancedText: "i will see you on tuesday afternoon",
                   finalText: "I will see you Tuesday afternoon instead", source: .edit,
                   appBundleID: nil, transcriptionID: tid, promptName: nil, in: c)
        #expect(all(c).count == 1)
        #expect(all(c)[0].editKind == .style)
    }

    @Test("retention prunes to newest 200")
    func prune() {
        let c = ctx()
        for i in 0..<205 {
            let rec = EnhancementEditRecord(rawText: "r", enhancedText: "e", finalText: "f\(i)",
                appBundleID: nil, transcriptionID: UUID(), enhancedHash: "h",
                editKind: .style, signalSource: .thumbsDown)
            rec.timestamp = Date().addingTimeInterval(Double(i))
            c.insert(rec)
        }
        try? c.save()
        svc.record(rawText: "raw", enhancedText: "enh", finalText: "x",
                   source: .thumbsDown, appBundleID: nil, transcriptionID: tid,
                   promptName: nil, in: c)
        #expect(all(c).count == 200)
    }

    @Test("cap eviction is oldest-first and type-agnostic; zero-edit rate not biased low")
    func pruneOldestFirstKeepsZeroEditRateUnbiased() {
        let c = ctx()
        // 20 OLDEST records are real .edit signals…
        for i in 0..<20 {
            let rec = EnhancementEditRecord(rawText: "r", enhancedText: "e", finalText: "edit\(i)",
                appBundleID: nil, transcriptionID: UUID(), enhancedHash: "h",
                editKind: .style, signalSource: .edit)
            rec.timestamp = Date().addingTimeInterval(Double(-100_000 + i))
            c.insert(rec)
        }
        // …followed by 190 newer .acceptedUnchanged (zero-edit) signals → 210 > cap.
        for i in 0..<190 {
            let rec = EnhancementEditRecord(rawText: "r", enhancedText: "e", finalText: "e",
                appBundleID: nil, transcriptionID: UUID(), enhancedHash: "h",
                editKind: .style, signalSource: .acceptedUnchanged)
            rec.timestamp = Date().addingTimeInterval(Double(-1_000 + i))
            c.insert(rec)
        }
        try? c.save()
        // Trigger the prune with one more real edit (211 → evict 11 oldest).
        svc.record(rawText: "raw", enhancedText: "enh", finalText: "different", source: .edit,
                   appBundleID: nil, transcriptionID: tid, promptName: nil, in: c)
        let kept = all(c)
        #expect(kept.count == 200)
        // Oldest-first: the 11 evicted are all old .edit rows; every
        // acceptedUnchanged survives. The retired class-preferential policy
        // evicted 11 accepts instead (keeping 20 edits + 179 accepts),
        // under-representing zero-edit signals.
        #expect(kept.filter { $0.signalSource == .acceptedUnchanged }.count == 190)
        #expect(kept.filter { $0.signalSource == .edit }.count == 10)
        // Bias check: rate over the retained sample = 190/200 = 0.95; the old
        // policy read 179/200 = 0.895 — artificially LOW.
        let rate = HistoryStats.zeroEditRate(editRecords: kept)
        #expect(abs(rate! - 0.95) < 0.0001)
    }
}
