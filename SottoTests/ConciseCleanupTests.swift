import Testing
import Foundation
@testable import Sotto

struct ConciseCleanupTests {

    @Test func dropsCrutchAdverbs() {
        #expect(ConciseCleanup.apply("I need to understand what is actually broken here.")
            == "I need to understand what is broken here.")
        #expect(ConciseCleanup.apply("The system should cache essentially.") == "The system should cache.")
        #expect(ConciseCleanup.apply("Basically, I want three things.") == "I want three things.")
    }

    @Test func shortensParticularAndEachAndEvery() {
        #expect(ConciseCleanup.apply("Use that particular thing.") == "Use that thing.")
        #expect(ConciseCleanup.apply("Each and every phase is done.") == "Every phase is done.")
        // "a particular" is a real choice of word, not a crutch.
        #expect(ConciseCleanup.apply("Put them into a particular block.") == "Put them into a particular block.")
    }

    @Test func dropsStackedOpenersAndRecapitalises() {
        #expect(ConciseCleanup.apply("Okay, so what is left?") == "What is left?")
        #expect(ConciseCleanup.apply("Done. Alright, let's do this.") == "Done. Let's do this.")
        #expect(ConciseCleanup.apply("So we would want to split them.") == "We would want to split them.")
    }

    @Test func keepsOpenersThatCarryMeaning() {
        #expect(ConciseCleanup.apply("So far, it works.") == "So far, it works.")
        #expect(ConciseCleanup.apply("So that direct pushes show up.") == "So that direct pushes show up.")
        #expect(ConciseCleanup.apply("Okay. Ship it.") == "Okay. Ship it.")
        #expect(ConciseCleanup.apply("Yes, merge it.") == "Yes, merge it.")
        #expect(ConciseCleanup.apply("I'll just let you know.") == "I'll let you know.")
        #expect(ConciseCleanup.apply("You get what I mean.") == "You get what I mean.")
    }

    @Test func dropsJustOnlyBeforeAVerb() {
        #expect(ConciseCleanup.apply("We should be able to just delete it.") == "We should be able to delete it.")
        #expect(ConciseCleanup.apply("Right now we have just one route.") == "Right now we have just one route.")
    }

    @Test func leavesCodeLinesAndDotNamesAlone() {
        #expect(ConciseCleanup.apply("git commit -m \"actually fix it\"") == "git commit -m \"actually fix it\"")
        #expect(ConciseCleanup.apply("Basically, use Rust or just .sh files.")
            == "Use Rust or just .sh files.")
    }

    @Test func keepsListMarkers() {
        #expect(ConciseCleanup.apply("Steps:\n- Basically, run the tests\n- Push the changes")
            == "Steps:\n- Run the tests\n- Push the changes")
    }

    @Test func isIdempotent() {
        let once = ConciseCleanup.apply("Okay, so basically, we can just delete that particular file.")
        #expect(once == "We can delete that file.")
        #expect(ConciseCleanup.apply(once) == once)
    }
}
