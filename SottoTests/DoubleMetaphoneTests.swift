import Testing
@testable import Sotto

@Suite struct DoubleMetaphoneTests {
    // Pinned reference encodings (standard Lawrence Philips algorithm, 4-char cap).
    @Test("empty string encodes to empty tuple")
    func empty() {
        let r = DoubleMetaphone.encode("")
        #expect(r.primary == "" && r.alternate == "")
    }
    @Test("Smith primary == SM0")
    func smith() {
        #expect(DoubleMetaphone.encode("Smith").primary == "SM0")
    }

    // Load-bearing matches from the real edit-capture data.
    @Test("cmux and cmax share a primary key (cmax→cmux mishear)")
    func cmuxCmax() {
        #expect(DoubleMetaphone.encode("cmux").primary == DoubleMetaphone.encode("cmax").primary)
    }
    @Test("sqlite self-matches and is case-insensitive")
    func sqliteSelf() {
        #expect(DoubleMetaphone.encode("sqlite").primary == DoubleMetaphone.encode("SQLite").primary)
        #expect(!DoubleMetaphone.encode("sqlite").primary.isEmpty)
    }
    @Test("anthropic and anthropomorphic share their (capped) primary prefix")
    func anthropic() {
        #expect(DoubleMetaphone.encode("anthropic").primary == DoubleMetaphone.encode("anthropomorphic").primary)
    }
    @Test("council and counselor share a primary key")
    func council() {
        #expect(DoubleMetaphone.encode("council").primary == DoubleMetaphone.encode("counselor").primary)
    }
    @Test("invoke and involve overlap on a primary prefix (partial — not a full match)")
    func invokeInvolve() {
        // Honest about reach: these only share a 3-char prefix, so the corrector
        // would NOT rewrite one to the other (keys differ). Pin the partial overlap.
        let a = DoubleMetaphone.encode("invoke").primary
        let b = DoubleMetaphone.encode("involve").primary
        let common = zip(a, b).prefix { $0 == $1 }.count
        #expect(common >= 3)
        #expect(a != b)
    }

    @Test("encoding is case-insensitive")
    func caseInsensitive() {
        #expect(DoubleMetaphone.encode("CMUX").primary == DoubleMetaphone.encode("cmux").primary)
    }
    @Test("non-letters are stripped before encoding")
    func stripsNonLetters() {
        #expect(DoubleMetaphone.encode("c.m-u x").primary == DoubleMetaphone.encode("cmux").primary)
    }
}
