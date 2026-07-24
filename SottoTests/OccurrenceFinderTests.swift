import Testing
import Foundation
@testable import Sotto

struct OccurrenceFinderTests {
    private let text = "cloud code talks to cloud and Cloud and cloud again"
    // occurrences of "cloud": 0-5, 20-25, 40-45 ("Cloud" at 30 is case-mismatched)

    @Test func findsNextAfterLocation() {
        let r = OccurrenceFinder.nextOccurrence(of: "cloud", in: text, after: 5, excluding: [NSRange(location: 0, length: 5)])
        #expect(r == NSRange(location: 20, length: 5))
    }

    @Test func wrapsAround() {
        let r = OccurrenceFinder.nextOccurrence(of: "cloud", in: text, after: 45, excluding: [NSRange(location: 40, length: 5)])
        #expect(r == NSRange(location: 0, length: 5))
    }

    @Test func skipsAlreadySelected() {
        let selected = [NSRange(location: 0, length: 5), NSRange(location: 20, length: 5)]
        let r = OccurrenceFinder.nextOccurrence(of: "cloud", in: text, after: 25, excluding: selected)
        #expect(r == NSRange(location: 40, length: 5))
    }

    @Test func allSelectedReturnsNil() {
        let selected = [NSRange(location: 0, length: 5), NSRange(location: 20, length: 5), NSRange(location: 40, length: 5)]
        let r = OccurrenceFinder.nextOccurrence(of: "cloud", in: text, after: 45, excluding: selected)
        #expect(r == nil)
    }

    @Test func caseSensitive() {
        let r = OccurrenceFinder.nextOccurrence(of: "cloud", in: text, after: 25, excluding: [NSRange(location: 20, length: 5)])
        #expect(r == NSRange(location: 40, length: 5)) // skips "Cloud" at 30
    }

    @Test func emptyQueryReturnsNil() {
        #expect(OccurrenceFinder.nextOccurrence(of: "", in: text, after: 0, excluding: []) == nil)
    }

    @Test func noMatchReturnsNil() {
        #expect(OccurrenceFinder.nextOccurrence(of: "zebra", in: text, after: 0, excluding: []) == nil)
    }

    @Test func nonOverlappingAdvance() {
        let r = OccurrenceFinder.nextOccurrence(of: "aa", in: "aaa", after: 0, excluding: [])
        #expect(r == NSRange(location: 0, length: 2))
        let r2 = OccurrenceFinder.nextOccurrence(of: "aa", in: "aaa", after: 0, excluding: [NSRange(location: 0, length: 2)])
        #expect(r2 == nil)
    }

    @Test func unicodeEmojiOffsets() {
        let s = "🎙️ cloud and cloud"
        let first = (s as NSString).range(of: "cloud")
        let r = OccurrenceFinder.nextOccurrence(of: "cloud", in: s, after: first.location + first.length, excluding: [first])
        #expect(r == (s as NSString).range(of: "cloud", options: .backwards))
    }
}
