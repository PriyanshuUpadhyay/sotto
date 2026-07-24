import Testing
import Foundation
@testable import Sotto

struct AppCategoryTests {

    @Test("email bundle ids map to .email", arguments: [
        "com.apple.mail",
        "com.microsoft.Outlook",
        "com.readdle.smartemail-Mac",
        "it.bloop.airmail2",
        "org.mozilla.thunderbird",
        "com.superhuman.electron",
    ])
    func emailBundles(_ id: String) {
        #expect(AppCategory.from(bundleID: id) == .email)
    }

    @Test("work messaging bundle ids map to .workMessaging", arguments: [
        "com.tinyspeck.slackmacgap",
        "com.microsoft.teams",
        "com.microsoft.teams2",
    ])
    func workMessagingBundles(_ id: String) {
        #expect(AppCategory.from(bundleID: id) == .workMessaging)
    }

    @Test("personal messaging bundle ids map to .personalMessaging", arguments: [
        "com.apple.MobileSMS",
        "net.whatsapp.WhatsApp",
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
        "com.hnc.Discord",
        "org.whispersystems.signal-desktop",
    ])
    func personalMessagingBundles(_ id: String) {
        #expect(AppCategory.from(bundleID: id) == .personalMessaging)
    }

    @Test("unknown, nil, and empty bundle ids map to .other", arguments: [
        String?.none, "", "com.example.unknown", "com.apple.Safari", "com.apple.mail.extra",
    ])
    func otherBundles(_ id: String?) {
        #expect(AppCategory.from(bundleID: id) == .other)
    }

    @Test("bundle id matching is case-insensitive")
    func caseInsensitive() {
        #expect(AppCategory.from(bundleID: "COM.APPLE.MAIL") == .email)
        #expect(AppCategory.from(bundleID: "com.TinySpeck.SlackMacGap") == .workMessaging)
    }

    /// `.personalMessaging`'s only mechanic is now applied deterministically in
    /// Swift, so like `.other` it contributes no prompt directive.
    @Test(".other and .personalMessaging contribute no register directive; email/work do")
    func registerDirectives() {
        #expect(AppCategory.other.registerDirective.isEmpty)
        #expect(AppCategory.personalMessaging.registerDirective.isEmpty)
        for category in [AppCategory.email, .workMessaging] {
            #expect(category.registerDirective.contains("REGISTER"))
        }
    }

    /// The register tunes punctuation mechanics only. Style/length words would
    /// contradict the cleanup rules' preserve-tone and no-paraphrase bounds.
    @Test("register directives carry the precedence framing and no style/length words")
    func registerDirectivesAreMechanicsOnly() {
        let banned = ["formal", "professional", "casual", "concise", "brief", "shorten", "tone"]
        for category in [AppCategory.email, .workMessaging] {
            let directive = category.registerDirective
            #expect(directive.contains("cleanup rules above always take precedence"))
            for word in banned {
                // "tone" appears only inside the precedence framing ("never change the speaker's tone").
                let body = directive.components(separatedBy: "\n").last ?? ""
                #expect(!body.lowercased().contains(word), "\(category) mechanic mentions '\(word)'")
            }
        }
    }

    // MARK: applyMechanics — deterministic per-category punctuation post-pass

    @Test("personalMessaging strips the trailing period on a short single sentence")
    func personalStripsShortSingleSentence() {
        #expect(AppCategory.personalMessaging.applyMechanics(to: "Sounds good.") == "Sounds good")
        #expect(AppCategory.personalMessaging.applyMechanics(to: "On my way.") == "On my way")
        #expect(AppCategory.personalMessaging.applyMechanics(to: "  See you at five.  ") == "See you at five")
    }

    @Test("personalMessaging keeps ? and ! and ellipsis")
    func personalKeepsOtherTerminals() {
        #expect(AppCategory.personalMessaging.applyMechanics(to: "Are you there?") == "Are you there?")
        #expect(AppCategory.personalMessaging.applyMechanics(to: "Let's go!") == "Let's go!")
        #expect(AppCategory.personalMessaging.applyMechanics(to: "Well…") == "Well…")
        #expect(AppCategory.personalMessaging.applyMechanics(to: "Hold on...") == "Hold on...")
    }

    @Test("personalMessaging leaves multi-sentence and multi-line output untouched")
    func personalKeepsMultiSentence() {
        #expect(AppCategory.personalMessaging.applyMechanics(to: "On my way. Be there soon.")
                == "On my way. Be there soon.")
        #expect(AppCategory.personalMessaging.applyMechanics(to: "Grab milk.\nAnd eggs.")
                == "Grab milk.\nAnd eggs.")
    }

    @Test("personalMessaging leaves a long single sentence and abbreviations/decimals untouched")
    func personalKeepsLongAndInteriorDot() {
        let long = "I will probably be running about twenty minutes late this evening."
        #expect(AppCategory.personalMessaging.applyMechanics(to: long) == long)
        #expect(AppCategory.personalMessaging.applyMechanics(to: "See you at 5 p.m.") == "See you at 5 p.m.")
        #expect(AppCategory.personalMessaging.applyMechanics(to: "It cost 3.50.") == "It cost 3.50.")
    }

    @Test("personalMessaging keeps the dot of a final-word abbreviation")
    func personalKeepsTrailingAbbreviation() {
        #expect(AppCategory.personalMessaging.applyMechanics(to: "Meet on Main St.") == "Meet on Main St.")
        #expect(AppCategory.personalMessaging.applyMechanics(to: "Bring snacks etc.") == "Bring snacks etc.")
        #expect(AppCategory.personalMessaging.applyMechanics(to: "Ask for Dr.") == "Ask for Dr.")
        #expect(AppCategory.personalMessaging.applyMechanics(to: "Bring snacks ETC.") == "Bring snacks ETC.")
    }

    @Test("non-personalMessaging categories are never modified", arguments: [
        AppCategory.email, .workMessaging, .other,
    ])
    func otherCategoriesUntouched(_ category: AppCategory) {
        #expect(category.applyMechanics(to: "Sounds good.") == "Sounds good.")
    }

    @Test("applyMechanics on empty input returns it unchanged")
    func emptyInputUnchanged() {
        #expect(AppCategory.personalMessaging.applyMechanics(to: "") == "")
        #expect(AppCategory.personalMessaging.applyMechanics(to: "   ") == "   ")
    }
}

struct CustomPromptCodableTests {

    /// `useSystemInstructions` was removed; old export files still carry it.
    /// Codable must ignore the unknown key rather than fail the whole import.
    @Test("decoding an export that still carries useSystemInstructions succeeds")
    func decodesLegacyExportWithRemovedKey() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "title": "Default",
          "promptText": "clean it up",
          "isActive": true,
          "icon": "checkmark.seal.fill",
          "description": "legacy",
          "isPredefined": true,
          "triggerWords": ["hey"],
          "useSystemInstructions": false
        }
        """.data(using: .utf8)!

        let prompt = try JSONDecoder().decode(CustomPrompt.self, from: json)

        #expect(prompt.title == "Default")
        #expect(prompt.triggerWords == ["hey"])
    }

    @Test("round-trip encode/decode drops the removed key")
    func roundTripOmitsRemovedKey() throws {
        let prompt = CustomPrompt(title: "T", promptText: "P", triggerWords: ["x"])
        let data = try JSONEncoder().encode(prompt)

        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(!json.contains("useSystemInstructions"))
        #expect(try JSONDecoder().decode(CustomPrompt.self, from: data) == prompt)
    }
}
