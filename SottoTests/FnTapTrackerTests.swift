import Testing
@testable import Sotto

struct FnTapTrackerTests {
    @Test func cleanTapFires() {
        var t = FnTapTracker()
        t.fnDown()
        #expect(t.fnUp() == true)
    }

    @Test func chordSuppresses() {
        var t = FnTapTracker()
        t.fnDown()
        t.otherKeyDown()
        #expect(t.fnUp() == false)
    }

    @Test func multipleChordKeysStillSuppress() {
        var t = FnTapTracker()
        t.fnDown()
        t.otherKeyDown()
        t.otherKeyDown()
        #expect(t.fnUp() == false)
    }

    @Test func keyDownWhileNotHeldIgnored() {
        var t = FnTapTracker()
        t.otherKeyDown()
        t.fnDown()
        #expect(t.fnUp() == true)
    }

    @Test func upWithoutDownDoesNotFire() {
        var t = FnTapTracker()
        #expect(t.fnUp() == false)
    }

    @Test func chordStateResetsForNextTap() {
        var t = FnTapTracker()
        t.fnDown()
        t.otherKeyDown()
        _ = t.fnUp()
        t.fnDown()
        #expect(t.fnUp() == true)
    }

    @Test func spuriousRedundantDownKeepsChordFlag() {
        var t = FnTapTracker()
        t.fnDown()
        t.otherKeyDown()
        t.fnDown() // macOS flags-changed blip mid-hold must not clear the chord
        #expect(t.fnUp() == false)
    }
}
