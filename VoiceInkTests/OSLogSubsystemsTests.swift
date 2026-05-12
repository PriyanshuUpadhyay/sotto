import Testing
import Foundation
@testable import VoiceInk

struct OSLogSubsystemsTests {

    @Test func app_subsystem_uses_sotto_bundle_id() {
        #expect(OSLogSubsystems.app == "com.sotto.Sotto")
    }

    @Test func fluidaudio_subsystem_namespaced_under_app() {
        #expect(OSLogSubsystems.fluidAudio.hasPrefix(OSLogSubsystems.app))
        #expect(OSLogSubsystems.fluidAudio == "com.sotto.Sotto.fluidaudio")
    }
}
