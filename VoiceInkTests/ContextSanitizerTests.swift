import Testing
import Foundation
@testable import VoiceInk

struct ContextSanitizerTests {

    @Test func redactsKeyShapeLines() async throws {
        let input = """
        normal line
        password=hunter2
        api_key: foo123
        secretary planned the meeting
        """
        let out = ContextSanitizer.sanitize(input, maxBytes: 10_000)
        #expect(!out.contains("hunter2"))
        #expect(!out.contains("foo123"))
        #expect(out.contains("secretary planned"))
    }

    @Test func redactsAuthHeaderShapes() async throws {
        let input = """
        Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.foo.bar
        x-api-key: abc/+xyz=
        nothing here
        """
        let out = ContextSanitizer.sanitize(input, maxBytes: 10_000)
        #expect(!out.contains("eyJhbGc"))
        #expect(!out.contains("abc/+xyz"))
        #expect(out.contains("nothing here"))
    }

    @Test func truncatesToTailWithMarker() async throws {
        let head = String(repeating: "A", count: 1000)
        let tail = String(repeating: "B", count: 500)
        let input = head + "\n" + tail
        let out = ContextSanitizer.sanitize(input, maxBytes: 600)
        #expect(out.contains("…[truncated]…"))
        #expect(out.contains("BBB"))
        #expect(!out.contains("AAAAAAA"))  // head dropped
    }

    @Test func idempotent() async throws {
        let input = "password=foo\nhello\n" + String(repeating: "Z", count: 5000)
        let once = ContextSanitizer.sanitize(input, maxBytes: 1000)
        let twice = ContextSanitizer.sanitize(once, maxBytes: 1000)
        #expect(once == twice)
    }

    @Test func smallInputUnchangedExceptRedaction() async throws {
        let input = "hello\nworld"
        let out = ContextSanitizer.sanitize(input, maxBytes: 10_000)
        #expect(out == input)  // no truncation marker on small inputs
    }
}
