import Foundation
import SwiftData

/// W12.E shim — exposes the app-level SwiftData container to static call
/// sites (chiefly `CursorPaster`). Wired during `VoiceInkApp.init` after the
/// container is created. Global singleton is acceptable v1; refactoring
/// `CursorPaster` to be instance-based is a much bigger change. See plan
/// `docs/superpowers/plans/W12E-scratchpad.md` §Task 8.2 + §Risks #13.
@MainActor
final class ScratchpadModelContainerProvider {
    static let shared = ScratchpadModelContainerProvider()
    private init() {}
    var modelContainer: ModelContainer?
}
