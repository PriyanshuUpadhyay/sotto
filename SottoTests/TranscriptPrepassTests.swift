import Testing
import Foundation
@testable import Sotto

struct TranscriptPrepassTests {

    // MARK: - Fillers

    @Test func dropsStandaloneFillers() {
        #expect(TranscriptPrepass.clean("um so uh push the changes") == "so push the changes")
        #expect(TranscriptPrepass.clean("er the build erm is broken") == "the build is broken")
        #expect(TranscriptPrepass.clean("hmm mm mhm ship it") == "ship it")
    }

    @Test func fillerMatchIsCaseInsensitiveAndWordBounded() {
        #expect(TranscriptPrepass.clean("Um push the changes") == "push the changes")
        // "umbrella" and "under" merely start with a filler's letters.
        #expect(TranscriptPrepass.clean("the umbrella is under the desk") == "the umbrella is under the desk")
    }

    @Test func leavesLikeAndYouKnowToTheModel() {
        #expect(TranscriptPrepass.clean("it was like you know fine") == "it was like you know fine")
    }

    // MARK: - Repeats

    @Test func collapsesRepeatedWord() {
        #expect(TranscriptPrepass.clean("check the the upload") == "check the upload")
        #expect(TranscriptPrepass.clean("we we should ship it") == "we should ship it")
    }

    @Test func collapsesRepeatedPhrase() {
        #expect(TranscriptPrepass.clean("for the for the release we freeze") == "for the release we freeze")
        #expect(TranscriptPrepass.clean("i want to i want to try this") == "i want to try this")
        #expect(TranscriptPrepass.clean("we need to test we need to test the migration")
                == "we need to test the migration")
    }

    @Test func keepsFirstOccurrenceCasing() {
        #expect(TranscriptPrepass.clean("The the cache is warm") == "The cache is warm")
    }

    @Test func doesNotCollapseAcrossAClauseBoundary() {
        #expect(TranscriptPrepass.clean("ship it, it is ready") == "ship it, it is ready")
        #expect(TranscriptPrepass.clean("that is that. That is all") == "that is that. That is all")
        // The sentence mark sits INSIDE the closing quote.
        #expect(TranscriptPrepass.clean("He shouted \u{201C}Wait!\u{201D} Wait for me.")
                == "He shouted \u{201C}Wait!\u{201D} Wait for me.")
        #expect(TranscriptPrepass.clean("she said \"stop.\" stop right there")
                == "she said \"stop.\" stop right there")
        #expect(TranscriptPrepass.clean("we shipped it (finally.) finally we can rest")
                == "we shipped it (finally.) finally we can rest")
    }

    // MARK: - Must not change

    @Test func keepsRepeatedNumerals() {
        #expect(TranscriptPrepass.clean("the code is 4 4 7 2") == "the code is 4 4 7 2")
        #expect(TranscriptPrepass.clean("call 555 555 1234") == "call 555 555 1234")
    }

    @Test func keepsRepeatedSpelledOutNumbers() {
        #expect(TranscriptPrepass.clean("call me on the extension two two five five")
                == "call me on the extension two two five five")
        #expect(TranscriptPrepass.clean("my extension is four four two two")
                == "my extension is four four two two")
    }

    @Test func ordinaryRepeatsStillCollapseBesideASpokenCode() {
        #expect(TranscriptPrepass.clean("the the code is two two") == "the code is two two")
    }

    @Test func keepsRepeatedSingleLetters() {
        #expect(TranscriptPrepass.clean("the ticket is a a b c") == "the ticket is a a b c")
    }

    // MARK: - Whitespace and structure

    @Test func normalisesWhitespace() {
        #expect(TranscriptPrepass.clean("  push   the\tchanges  ") == "push the changes")
    }

    @Test func preservesLineStructure() {
        let listed = "My tasks are:\n1. Update the brief\n2. Send it to Mina"
        #expect(TranscriptPrepass.clean(listed) == listed)
        #expect(TranscriptPrepass.clean("That's the summary.\n\nNext, pricing.")
                == "That's the summary.\n\nNext, pricing.")
    }

    @Test func neverCollapsesAcrossALineBreak() {
        #expect(TranscriptPrepass.clean("1. The migration\n2. The migration")
                == "1. The migration\n2. The migration")
    }

    @Test func emptyInputStaysEmpty() {
        #expect(TranscriptPrepass.clean("   ") == "")
    }

    // MARK: - Edge punctuation on a removed repeat

    @Test func keepsTrailingPunctuationFromTheRemovedCopy() {
        #expect(TranscriptPrepass.clean("Wait wait!") == "Wait!")
        #expect(TranscriptPrepass.clean("\u{201C}Wait wait!\u{201D}") == "\u{201C}Wait!\u{201D}")
        #expect(TranscriptPrepass.clean("\"Wait wait!\"") == "\"Wait!\"")
        #expect(TranscriptPrepass.clean("check the the upload.") == "check the upload.")
        #expect(TranscriptPrepass.clean("ship it we we can;") == "ship it we can;")
    }

    /// The kept copy already closes its own quote, so the removed copy's
    /// closing quote must not be appended on top of it.
    @Test func doesNotDoubleUpPunctuationTheKeptCopyAlreadyHas() {
        #expect(TranscriptPrepass.clean("\u{201C}Wait\u{201D} \u{201C}wait\u{201D}")
                == "\u{201C}Wait\u{201D}")
    }

    @Test func handlesApostrophesAndHyphens() {
        #expect(TranscriptPrepass.clean("it\u{2019}s it\u{2019}s fine") == "it\u{2019}s fine")
        #expect(TranscriptPrepass.clean("don\u{2019}t don\u{2019}t!") == "don\u{2019}t!")
        #expect(TranscriptPrepass.clean("a well-known well-known result") == "a well-known result")
    }

    // MARK: - CRLF and Unicode whitespace

    @Test func normalisesCarriageReturns() {
        #expect(TranscriptPrepass.clean("um\r\nship it") == "ship it")
        #expect(TranscriptPrepass.clean("first line\r\n\r\nsecond line")
                == "first line\n\nsecond line")
    }

    @Test func splitsOnUnicodeWhitespace() {
        #expect(TranscriptPrepass.clean("um\u{00A0}ship it") == "ship it")
        #expect(TranscriptPrepass.clean("check the\u{2009}the upload") == "check the upload")
    }

    // MARK: - Idempotence

    @Test func collapsesOverlappingRepeatsInOnePass() {
        #expect(TranscriptPrepass.clean("please send please please send") == "please send")
    }

    @Test func cleaningTwiceChangesNothingFurther() {
        let inputs = [
            "um so uh push the changes", "check the the upload", "for the for the release we freeze",
            "please send please please send", "the code is 4 4 7 2", "the ticket is a a b c",
            "call me on the extension two two five five", "\u{201C}Wait wait!\u{201D}",
            "ship it, it is ready", "My tasks are:\n1. Update the brief\n2. Send it to Mina",
            "That\u{2019}s the summary.\n\nNext, pricing.", "um\r\nship it",
            "um\u{00A0}ship it", "we we should probably probably wait for review", "   ",
        ]
        for input in inputs {
            let once = TranscriptPrepass.clean(input)
            #expect(TranscriptPrepass.clean(once) == once, "not idempotent for: \(input)")
        }
    }

    // MARK: - finish: prose only

    @Test func addsTheCapitalAndTheTerminalMarkAModelOutputLacks() {
        #expect(TranscriptPrepass.finish("the deploy script is broken") == "The deploy script is broken.")
        #expect(TranscriptPrepass.finish("did the build finish") == "Did the build finish?")
        #expect(TranscriptPrepass.finish("what is the status here") == "What is the status here?")
        #expect(TranscriptPrepass.finish("how many retries are left") == "How many retries are left?")
    }

    @Test func finishLeavesCodeLikeLinesExactlyAsTheyAre() {
        // Finding 3: every one of these was corrupted before.
        #expect(TranscriptPrepass.finish("npm install lodash") == "npm install lodash")
        #expect(TranscriptPrepass.finish("git push origin main") == "git push origin main")
        #expect(TranscriptPrepass.finish("https://example.com") == "https://example.com")
        #expect(TranscriptPrepass.finish("/tmp/build.log") == "/tmp/build.log")
        #expect(TranscriptPrepass.finish("main") == "main")
        #expect(TranscriptPrepass.finish("run `make test` first") == "run `make test` first")
    }

    @Test func finishNeverPunctuatesAListItem() {
        // Finding 3: a one-item list got a sentence mark it does not own.
        #expect(TranscriptPrepass.finish("- install dependencies") == "- Install dependencies")
        #expect(TranscriptPrepass.finish("1. freeze the branch") == "1. Freeze the branch")
    }

    @Test func finishMarksOnlyRealQuestionSyntax() {
        // Finding 7: a first word alone is not a question.
        #expect(TranscriptPrepass.finish("what I mean is we ship on friday")
                == "What I mean is we ship on friday.")
        #expect(TranscriptPrepass.finish("what I need is a fix") == "What I need is a fix.")
        #expect(TranscriptPrepass.finish("how this works is simple") == "How this works is simple.")
        #expect(TranscriptPrepass.finish("do it now") == "Do it now.")
        #expect(TranscriptPrepass.finish("did it work") == "Did it work?")
        #expect(TranscriptPrepass.finish("can you rebase this") == "Can you rebase this?")
    }

    // MARK: - lineBreaks: an own-line cue only

    @Test func honorsACueOnItsOwnLine() {
        #expect(TranscriptPrepass.lineBreaks("the deck is ready\nnew line\nI will send the link")
                == "the deck is ready.\nI will send the link")
        #expect(TranscriptPrepass.lineBreaks("that is all\nnew paragraph\nwe ship on Monday")
                == "that is all.\n\nwe ship on Monday")
    }

    @Test func anInlineCueIsOrdinaryContent() {
        // Finding 4: these are instructions to a coding agent, not cues.
        #expect(TranscriptPrepass.lineBreaks("replace new line with a space")
                == "replace new line with a space")
        #expect(TranscriptPrepass.lineBreaks("the phrase new line is ambiguous")
                == "the phrase new line is ambiguous")
        #expect(TranscriptPrepass.lineBreaks("whats the timeout new line its twenty seconds")
                == "whats the timeout new line its twenty seconds")
        #expect(TranscriptPrepass.lineBreaks("1. install new line 2. test")
                == "1. install new line 2. test")
    }

    @Test func aCueLineNeverPunctuatesAListItemBeforeIt() {
        #expect(TranscriptPrepass.lineBreaks("1. install the CLI\nnew line\n2. run it")
                == "1. install the CLI\n2. run it")
    }

    // MARK: - contractions: forms that are never ordinary words

    @Test func restoresTheApostropheOnUnambiguousFormsOnly() {
        #expect(TranscriptPrepass.contractions("whats the plan, I dont know")
                == "what\u{2019}s the plan, I don\u{2019}t know")
        #expect(TranscriptPrepass.contractions("Thats mine") == "That\u{2019}s mine")
    }

    @Test func contractionsLeaveOrdinaryWordsCodeAndAcronymsAlone() {
        // Finding 6: every one of these was corrupted before.
        #expect(TranscriptPrepass.contractions("the API lets callers retry") == "the API lets callers retry")
        #expect(TranscriptPrepass.contractions("IM the user now") == "IM the user now")
        #expect(TranscriptPrepass.contractions("use `dont` as the key") == "use `dont` as the key")
        #expect(TranscriptPrepass.contractions("CANT WONT DONT") == "CANT WONT DONT")
        #expect(TranscriptPrepass.contractions("its well past the ill-timed id check")
                == "its well past the ill-timed id check")
    }

    // MARK: - emphasis: valid Markdown outside code only

    @Test func stripsOnlyAValidMarkdownBoldPair() {
        #expect(TranscriptPrepass.emphasis("a **shit** show") == "a shit show")
    }

    @Test func emphasisLeavesCodeAndOperatorsAlone() {
        // Finding 2: every one of these was corrupted before.
        #expect(TranscriptPrepass.emphasis("use `__init__` here") == "use `__init__` here")
        #expect(TranscriptPrepass.emphasis("**kwargs, **options") == "**kwargs, **options")
        #expect(TranscriptPrepass.emphasis("use `**kwargs` and `**args`") == "use `**kwargs` and `**args`")
        #expect(TranscriptPrepass.emphasis("x ** y ** z") == "x ** y ** z")
        #expect(TranscriptPrepass.emphasis("__really__ slow") == "__really__ slow")
        #expect(TranscriptPrepass.emphasis("call parse_audio_buffer") == "call parse_audio_buffer")
    }

    /// The production order, exactly as `AIEnhancementService.makeRequest` runs it.
    private func chain(_ raw: String) -> String {
        TranscriptPrepass.finish(TranscriptPrepass.emphasis(TranscriptPrepass.contractions(
            TranscriptPrepass.lineBreaks(TranscriptPrepass.clean(raw)))))
    }

    // MARK: - Round 4: no number is ever rewritten

    /// The `numerals` pass is gone. Three reviews could not make it safe, so
    /// every spoken number now reaches the user exactly as the model wrote it.
    @Test func theChainNeverRewritesASpokenNumber() {
        for input in ["nine eleven", "count one two three", "zero seven", "version twenty-one",
                      "the timeout is thirty seconds", "the code is five five five one two three four",
                      "my number is one two three", "we shipped forty two builds"] {
            #expect(chain(input) == TranscriptPrepass.finish(TranscriptPrepass.clean(input)),
                    "a number moved in: \(input)")
            #expect(!chain(input).contains(where: { $0.isNumber }), "a numeral appeared in: \(input)")
        }
    }

    /// The guard is `main`'s again, so the grounding it always did still works
    /// and the round-3 string rules are gone with the pass that needed them.
    @Test func theGuardIsMainsAgain() {
        #expect(EnhancementSanityCheck.detect(raw: "wait twenty five minutes",
                                              output: "Wait 25 minutes.").isClean)
        #expect(EnhancementSanityCheck.detect(raw: "the timeout is thirty seconds",
                                              output: "The timeout is 600 seconds.").isSuspect)
        #expect(EnhancementSanityCheck.detect(raw: "ship the build today",
                                              output: "Ship the 7 builds today.").isSuspect)
    }

    // MARK: - Round 4: fences

    @Test func onlyAMatchingDelimiterClosesAFence() {
        // Finding 4: a `~~~` line inside a ``` block toggled the fence off.
        let mixed = "```swift\n~~~\ndont change thirty here\n```"
        #expect(chain(mixed) == mixed)
        let inverse = "~~~\n```\ndont change thirty here\n~~~"
        #expect(chain(inverse) == inverse)
    }

    @Test func aFenceIsFoundAfterAListMarkerOrIndentation() {
        // Finding 4: the list marker hid the fence from the prefix check.
        let listed = "- ```swift\ndont change thirty here\n- ```"
        #expect(chain(listed) == listed)
        // `clean` normalises indentation before any pass sees the text, so the
        // indented case is checked where it matters: the classifier itself.
        #expect(TranscriptPrepass.codeLikeLines(["    ```", "dont change thirty here", "    ```"])
                == [true, true, true])
    }

    @Test func anUnterminatedFenceProtectsEveryLineAfterIt() {
        let open = "```\ndont change thirty here\nstill inside"
        #expect(chain(open) == open)
    }

    // MARK: - Round 4: an ambiguous tool name defaults to code

    @Test func anUnknownCommandShapeKeepsItsCommandReading() {
        // Finding 5: every one of these was corrupted before.
        for command in ["make deploy-staging", "go version", "cat README", "touch LICENSE",
                        "echo hello", "make -j8", "go run main.go", "cd ~", "echo $PATH",
                        "cat README.md", "swift build"] {
            #expect(TranscriptPrepass.finish(command) == command, "changed: \(command)")
        }
    }

    @Test func onlyANarrowProseOpeningOverridesTheCommandReading() {
        #expect(TranscriptPrepass.finish("go to the settings") == "Go to the settings.")
        #expect(TranscriptPrepass.finish("make the button blue") == "Make the button blue.")
        #expect(TranscriptPrepass.finish("make sure it works") == "Make sure it works.")
        #expect(TranscriptPrepass.finish("cat is on the keyboard") == "Cat is on the keyboard.")
        #expect(TranscriptPrepass.finish("touch the icon") == "Touch the icon.")
        #expect(TranscriptPrepass.finish("echo that back to me") == "Echo that back to me.")
        #expect(TranscriptPrepass.finish("swift is fast") == "Swift is fast.")
        #expect(TranscriptPrepass.finish("cd into the folder") == "Cd into the folder.")
    }

    // MARK: - the whole chain

    @Test func everyPassLeavesACodeLineAlone() {
        // Finding 5: contractions ignored the shared classifier.
        #expect(TranscriptPrepass.contractions("/dont") == "/dont")
        #expect(TranscriptPrepass.contractions("git dont") == "git dont")
        #expect(TranscriptPrepass.contractions("dont") == "dont")
        #expect(TranscriptPrepass.contractions("~~~\ndont\n~~~") == "~~~\ndont\n~~~")
        #expect(TranscriptPrepass.contractions("```\ndont\n```") == "```\ndont\n```")
    }

    @Test func aContractionAtTheStartStillGetsItsCapital() {
        // Finding 6: the apostrophe blocked the capital.
        #expect(chain("whats the status") == "What\u{2019}s the status?")
        #expect(TranscriptPrepass.finish("what\u{2019}s the status") == "What\u{2019}s the status?")
    }

    @Test func anOwnLineCueUsesSentenceAwareTermination() {
        // Finding 7: the cue path always appended a period.
        #expect(chain("what is the timeout\nnew line\nit is twenty seconds")
                == "What is the timeout?\nIt is twenty seconds.")
        #expect(TranscriptPrepass.lineBreaks("\"ship it\"\nnew line\nthen wait")
                == "\"ship it.\"\nthen wait")
    }

    @Test func whatIfIsAQuestionAndASubjectQuestionIsNot() {
        // Finding 8.
        #expect(TranscriptPrepass.finish("what if we ship") == "What if we ship?")
        #expect(TranscriptPrepass.finish("what happened to the build") == "What happened to the build.")
    }

    // MARK: - Shared with the repair guard's fallback

    @Test func deterministicCleanupBuildsOnThePrepass() {
        #expect(EnhancementSanityCheck.deterministicCleanup("um so uh push the the changes")
                == "So push the changes.")
    }
}
