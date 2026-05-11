import Testing
import Foundation
@testable import VoiceInk

struct PowerModeClipboardContextDecodingTests {

    @Test func decodingLegacyJSONWithoutFieldDefaultsToFalse() throws {
        let json = #"""
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "Legacy",
            "emoji": "🧪",
            "enhanceLevel": "medium",
            "useScreenCapture": false,
            "autoSendKey": "none",
            "isEnabled": true,
            "isDefault": false
        }
        """#.data(using: .utf8)!

        let config = try JSONDecoder().decode(PowerModeConfig.self, from: json)
        #expect(config.useClipboardContext == false)
    }

    @Test func decodingJSONWithUseClipboardContextTrueYieldsTrue() throws {
        let json = #"""
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "name": "WithFlag",
            "emoji": "🚀",
            "enhanceLevel": "medium",
            "useScreenCapture": false,
            "useClipboardContext": true,
            "autoSendKey": "none",
            "isEnabled": true,
            "isDefault": false
        }
        """#.data(using: .utf8)!

        let config = try JSONDecoder().decode(PowerModeConfig.self, from: json)
        #expect(config.useClipboardContext == true)
    }

    @Test func decodingJSONWithUseClipboardContextFalseYieldsFalse() throws {
        let json = #"""
        {
            "id": "33333333-3333-3333-3333-333333333333",
            "name": "FlagFalse",
            "emoji": "🌀",
            "enhanceLevel": "medium",
            "useScreenCapture": false,
            "useClipboardContext": false,
            "autoSendKey": "none",
            "isEnabled": true,
            "isDefault": false
        }
        """#.data(using: .utf8)!

        let config = try JSONDecoder().decode(PowerModeConfig.self, from: json)
        #expect(config.useClipboardContext == false)
    }

    @Test func encodeDecodeRoundTripPreservesValue() throws {
        for value in [true, false] {
            let original = PowerModeConfig(
                id: UUID(),
                name: "RoundTrip",
                emoji: "🔁",
                useClipboardContext: value
            )
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(PowerModeConfig.self, from: data)
            #expect(decoded.useClipboardContext == value)
        }
    }
}
