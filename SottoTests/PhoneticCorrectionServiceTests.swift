import Testing
@testable import Sotto

@Suite struct PhoneticCorrectionServiceTests {
    private let svc = PhoneticCorrectionService.shared

    // POSITIVE: OOV token phonetically matches a vocab term within the gate.
    @Test("cmax → cmux (OOV, phonetic + Levenshtein match)")
    func correctsCmax() {
        let out = svc.correct("deploy to cmax", vocabulary: ["cmux"], isMisspelled: { $0 == "cmax" })
        #expect(out == "deploy to cmux")
    }

    // HONEST LIMIT: dcl8 is NOT phonetically close to sqlite → left unchanged.
    @Test("dcl8 stays unchanged (not phonetically close to sqlite)")
    func leavesDcl8() {
        let out = svc.correct("open dcl8 db", vocabulary: ["sqlite"], isMisspelled: { $0 == "dcl8" })
        #expect(out == "open dcl8 db")
    }

    // HONEST LIMIT: counselor→council shares a phonetic key but exceeds the
    // Levenshtein gate (max(1, 7/4)=1, surface distance is far larger) → unchanged.
    @Test("counselor stays unchanged (phonetic match but outside Levenshtein gate)")
    func leavesCounselor() {
        let out = svc.correct("ask the counselor", vocabulary: ["council"], isMisspelled: { $0 == "counselor" })
        #expect(out == "ask the counselor")
    }

    // NEGATIVE (load-bearing): valid English words are never candidates.
    @Test("valid words never touched even if a near-homophone vocab term exists")
    func validWordsUntouched() {
        let out = svc.correct("cloud computing scales", vocabulary: ["claude", "skill"], isMisspelled: { _ in false })
        #expect(out == "cloud computing scales")
    }

    // NEGATIVE (load-bearing last line of defense): even when OOV AND the
    // DoubleMetaphone primary keys collide (cloud→KLT == claude→KLT), the
    // surface Levenshtein distance (2) exceeds the gate (max(1, 6/4)=1), so the
    // rewrite is blocked. This exercises the distance gate specifically.
    @Test("cloud stays unchanged even when forced OOV (Levenshtein gate blocks key-collision)")
    func distanceGateBlocksKeyCollision() {
        let out = svc.correct("cloud computing", vocabulary: ["claude"], isMisspelled: { _ in true })
        #expect(out == "cloud computing")
    }

    // NEGATIVE: OOV but no phonetic match → unchanged.
    @Test("OOV with no phonetic match is left unchanged")
    func oovNoMatchUntouched() {
        let out = svc.correct("the xyzzy thing", vocabulary: ["claude"], isMisspelled: { $0 == "xyzzy" })
        #expect(out == "the xyzzy thing")
    }

    // Punctuation + sentence-leading capital preserved.
    @Test("punctuation and leading capital preserved on correction")
    func preservesPunctuationAndCase() {
        let out = svc.correct("Cmax, then go", vocabulary: ["cmux"], isMisspelled: { $0.lowercased() == "cmax" })
        #expect(out == "Cmux, then go")
    }

    // Already-exact vocab term is not a candidate (case-insensitive).
    @Test("exact vocab term is not re-corrected")
    func exactTermSkipped() {
        let out = svc.correct("run cmux now", vocabulary: ["cmux"], isMisspelled: { _ in true })
        #expect(out == "run cmux now")
    }

    // REGRESSION (live edit data, 2026-06-25): ASR emits short domain terms
    // ALL-CAPS ("CMAX"). NSSpellChecker treats all-caps tokens as acronyms and
    // never flags them, so the OOV gate must normalize case before checking —
    // else the flagship cmax→cmux correction silently never fires.
    @Test("all-caps ASR token corrected (OOV gate normalizes case)")
    func correctsAllCapsToken() {
        // Mimics NSSpellChecker: an all-caps token is never reported misspelled.
        let nsLike: (String) -> Bool = { $0 != $0.uppercased() && $0.lowercased() == "cmax" }
        let out = svc.correct("the CMAX repo", vocabulary: ["cmux"], isMisspelled: nsLike)
        #expect(out == "the Cmux repo")
    }

    // ── Acoustic confirmation gate (opt-in CTC boosting) ──────────────────────

    // GATE: an OOV mishear is corrected only toward an acoustically-confirmed term.
    @Test("confirmed-set gate blocks correction toward an unconfirmed term")
    func acousticGateBlocksUnconfirmed() {
        let out = svc.correct("deploy to cmax", vocabulary: ["cmux"],
                              isMisspelled: { $0 == "cmax" }, acousticallyConfirmed: [])
        #expect(out == "deploy to cmax")
    }

    @Test("confirmed-set gate allows correction toward a confirmed term")
    func acousticGateAllowsConfirmed() {
        let out = svc.correct("deploy to cmax", vocabulary: ["cmux"],
                              isMisspelled: { $0 == "cmax" }, acousticallyConfirmed: ["cmux"])
        #expect(out == "deploy to cmux")
    }

    // UNLOCK: with confirmation, a VALID (non-OOV) word may be rewritten toward a
    // confirmed term — the homophone unlock. Uses the verified cmax↔cmux key pair
    // with cmax treated as non-OOV.
    @Test("confirmation unlocks rewrite of a valid (non-OOV) word toward a confirmed term")
    func acousticUnlockRewritesValidWord() {
        let out = svc.correct("deploy cmax", vocabulary: ["cmux"],
                              isMisspelled: { _ in false }, acousticallyConfirmed: ["cmux"])
        #expect(out == "deploy cmux")
    }

    @Test("without confirmation a valid word is never rewritten (unlock is off)")
    func acousticUnlockOffWithoutConfirmation() {
        let out = svc.correct("deploy cmax", vocabulary: ["cmux"], isMisspelled: { _ in false })
        #expect(out == "deploy cmax")
    }

    // HARD ANCHOR: acoustic confirmation is strong evidence the term was spoken,
    // so a confirmed term widens the Levenshtein gate (max(2, count/2) vs the
    // normal max(1, count/4)). cloud→claude shares the DoubleMetaphone key and is
    // surface-distance 2; the normal gate (1) blocks it, but the confirmed gate
    // (max(2, 6/2)=3) admits it. So "cloud" rewrites toward a confirmed "claude".
    @Test("confirmed term widens the distance gate (hard anchor): cloud → claude")
    func acousticConfirmedWidensDistanceGate() {
        let out = svc.correct("cloud code", vocabulary: ["claude"],
                              isMisspelled: { _ in false }, acousticallyConfirmed: ["claude"])
        #expect(out == "claude code")
    }

    @Test("empty vocabulary is a no-op")
    func emptyVocab() {
        let out = svc.correct("deploy to cmax", vocabulary: [], isMisspelled: { _ in true })
        #expect(out == "deploy to cmax")
    }

    // ── correctDetailed: structured trace detail ──────────────────────────────

    @Test("correctDetailed reports an OOV correction (reason, from/to/distance)")
    func detailedReportsOOV() {
        let r = svc.correctDetailed("deploy to cmax", vocabulary: ["cmux"],
                                    isMisspelled: { $0 == "cmax" })
        #expect(r.text == "deploy to cmux")
        #expect(r.corrections.count == 1)
        let c = r.corrections[0]
        #expect(c.token == "cmax")
        #expect(c.from == "cmax")
        #expect(c.to == "cmux")
        #expect(c.reason == "oov")
        #expect(c.distance == 1)
    }

    @Test("correctDetailed reports reason homophone-unlock for a confirmed valid word")
    func detailedReportsHomophoneUnlock() {
        let r = svc.correctDetailed("deploy cmax", vocabulary: ["cmux"],
                                    isMisspelled: { _ in false }, acousticallyConfirmed: ["cmux"])
        #expect(r.text == "deploy cmux")
        #expect(r.corrections.count == 1)
        #expect(r.corrections[0].reason == "homophone-unlock")
    }

    @Test("correctDetailed reports no corrections when nothing changes")
    func detailedReportsEmpty() {
        let r = svc.correctDetailed("hello world", vocabulary: ["cmux"], isMisspelled: { _ in false })
        #expect(r.text == "hello world")
        #expect(r.corrections.isEmpty)
    }

    @Test("correctDetailed .text and correct(...) both produce the expected correction")
    func detailedTextMatchesCorrect() {
        let misspelled: (String) -> Bool = { $0 != $0.uppercased() && $0.lowercased() == "cmax" }
        // Hardcoded expectation (not a method-vs-method tautology): CMAX → Cmux,
        // leading capital preserved, surrounding tokens untouched.
        #expect(svc.correct("the CMAX repo", vocabulary: ["cmux"], isMisspelled: misspelled) == "the Cmux repo")
        #expect(svc.correctDetailed("the CMAX repo", vocabulary: ["cmux"], isMisspelled: misspelled).text == "the Cmux repo")
    }
}
