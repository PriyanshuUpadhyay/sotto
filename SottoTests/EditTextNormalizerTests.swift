import Testing
import CryptoKit
@testable import Sotto

@Suite struct EditTextNormalizerTests {
    @Test("collapses whitespace and trims for hashing")
    func normalizeCollapsesWhitespace() {
        #expect(EditTextNormalizer.normalize("hello   world\n") == "hello world")
        #expect(EditTextNormalizer.normalize("  a\tb  ") == "a b")
    }
    @Test("hash is stable across whitespace-only differences")
    func hashStable() {
        #expect(EditTextNormalizer.hash("hello world") == EditTextNormalizer.hash("hello   world\n"))
    }
}
