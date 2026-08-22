// TheMasterToneHasADoorTests.swift
// Echoel — a documented four-way master-bus character that nothing could choose. #736.
//
// WHAT WAS WRONG. `AutoMixChain.Preset` has four named curves — balanced, warm, bright,
// transparent — over the same three EQ bands, and `applyPreset()` writes real gains on the
// master bus. `AudioEngine` constructs the chain and inserts it into the graph, so it is as
// live as audio gets. And from 2026-06-23 until this commit **`preset` had no writer
// anywhere**: every session ran `.balanced` and the other three were unreachable.
//
// ⭐ IT IS THE FIRST THING `scripts/doorless-state.py`'s MASKED SECTION FOUND, which is why
// the section exists. The detector's write matcher is keyed on the bare identifier, so two
// unrelated `self.preset = preset` lines in `BioSignalDeconvolver` and `BioSpaceMap` hid it
// completely — #734 shipped without seeing it, the #734 review found it by hand, and #735
// added the section that surfaces exactly this class. The tool now reports `preset` as
// written in its own file, which is what a door looks like from the outside.
//
// ⚠️ ONE OWNER, TWO CALLERS — the `MIDIOutput.applyOutputPreferences()` shape, and claim 3
// is what pins it. The Picker's `.onChange` calls `applyPersistedPreset()`, the SAME method
// `configureEQ()` calls while `AudioEngine` builds the graph. Neither maps the stored raw
// value to a `Preset` a second time, so a persisted choice and a live tap cannot disagree.
// #714 is the cycle that paid for a launch path which "obviously" ran and did not.
//
// ⚠️ LABELLED "Tone", NOT "Character": `EchoelStudioView` already has two
// `labeledRow("Character")` rows — the sound preset row and the Effects picker — and a third
// meaning of one word in one app is worse than a longer label.
//
// ⛔ AND #736 MEASURED THE WORD IT REJECTED WITHOUT MEASURING THE WORD IT CHOSE (#737).
// `groupHeader("Tone")` already exists in the Sound panel (the synth-timbre group:
// Brightness / Harmonics / Noise / Shape). So the slice avoided a third "Character" by
// creating a **second "Tone"**. The choice still stands — different panel, a group HEADER
// rather than a row label, and the master row is unambiguous in place — but it is weaker
// than the collision it avoided, and the original paragraph presented a measurement it had
// not run on its own pick. **A justification that counts the alternatives must count the
// choice.**
//
// LIMITS, STATED FIRST (§1). Claims 1-2 and 8-10 are END-TO-END BEHAVIOUR over shipped value
// types — 8-10 only became possible with #740, which lifted the curves and the stored-token
// resolution out of the `@MainActor` class as pure values. Claims 3-7 remain a SOURCE-TEXT
// SCAN: `applyPreset()` writes into an `AVAudioUnitEQ` and `masterPanel`'s members are
// `private` on a `View`, so the hand-off itself cannot be driven here. That the four curves
// SOUND different, and that Warm actually reads warm, is a DEVICE PROBE and stays open — it
// is also the only thing that matters to the founder's ear. **Claim 8 proves the four curves
// are DIFFERENT; nothing here proves any of them is GOOD.**
//
// ⚠️ HONEST GRADING (#433/#464/#486) — AND IT IS TWO EPOCHS, WHICH #740 BOLTED TOGETHER AND
// #741 SEPARATES. This block was written for #736 against ITS parent `e837ccb`; #740 then
// added bullets graded against ITS parent `c2895c8` into the same list. The result named two
// different commits as "the parent" nine lines apart, and its "Claims 3-5 are REGRESSIONS"
// bullet — true of `e837ccb` — was FALSE of `c2895c8`, where all three are green. **A grading
// block is a statement about ONE tree; a guard that survives several commits accumulates
// several, and they have to stay labelled or they start contradicting each other.**
//
// EPOCH 1 — #736 against `e837ccb`. The file named `AutoMixChain.Preset.allCases` and
// `StudioDefaultKeys.masterCharacter`, both created by #736, so it **did not compile against
// `e837ccb` and no assertion had a verdict there** (#488 shipped a red gate for a cycle behind
// exactly that ambiguity). Hand-transcribed in Python against both trees at the time:
//   · Claims 1-2 were FORWARD guards (#433) — they drive symbols #736 added and could never
//     have been red. What earns them a place is that they check the two failure modes a
//     compiler cannot: a stored default that does not PARSE (silently identical to a working
//     one), and two characters sharing a display name.
//   · ⛔ ONE SUB-ASSERTION INSIDE CLAIM 1 IS A MIRROR AND IS NOW LABELLED AS ONE (#367/#737).
//     `XCTAssertEqual(Preset(rawValue: p.rawValue), p)` cannot fail against the shipped enum:
//     `Preset` is a plain `String`-raw enum, so the compiler synthesises `rawValue` and
//     `init?(rawValue:)` from ONE case table and rejects duplicate raw values outright. There
//     is no mutation of today's code that makes it red — which is exactly what #367 forbids
//     counting as evidence. It is KEPT, not deleted, because it stops being a mirror the day
//     anyone writes a custom `init?(rawValue:)` (a normaliser that lower-cases, a migration
//     that maps an old token), and that is the day a case would stop round-tripping in
//     silence. Read it as a FORWARD tripwire on a hand-written initialiser, never as proof
//     that persistence works. The two sibling assertions in the same method — distinct
//     `displayName`s, non-empty `displayName` — are genuine and CAN fail today.
//   · Claims 3-5 were REGRESSIONS on `e837ccb`: it has no Picker, no launch call, and spells
//     the `.balanced` gains twice. Counted as ONE finding — the door's absence (#486).
//   · Claim 6 is a COUNTERWEIGHT, green on every tree in this chain. Without it, deleting the
//     chain from the graph would leave the door green over a control that moves nothing.
//
// EPOCH 2 — #740 against `c2895c8`, re-transcribed for #741:
//   · Claims 1-6 are ALL GREEN on `c2895c8` — measured, not assumed. Everything #736 built is
//     already there, so relative to #740's parent they are counterweights, not regressions.
//   · Claim 7 is re-anchored by #740 and is ANCHOR-ABSENT on `c2895c8` (the branches lived in
//     `applyPreset()` there, not on `Preset.gains`) — a FAIL, not a skip, which is the right
//     reading per #454 since the FILE exists and only the member moved.
//   · Claims 8-10 are FORWARD (#433): they name `Preset.gains` and `Preset.resolved(from:)`,
//     both created by #740, so they do not compile against `c2895c8` and have no verdict
//     there. What earns them their place is that they close the two gaps #737 registered and
//     could not close — an identical-curve collapse, and a stored-token resolution with no
//     behavioural coverage at all.
//
// ⚠️ STRIPPER (#453/#477): **TRAGEND (1 of 12)** — corrected in #737 after the #736 review,
// and the correction is in BOTH halves of the label.
//   · The DENOMINATOR was 3. This file reads **12** needles from source: claim 3 two,
//     claim 4 one, claim 5 three (negative), claim 6 two, claim 7 four. The 3 counted only
//     claim 5's negatives, i.e. the claim I happened to be thinking about. ⭐ RE-MEASURED
//     AFTER #740 and unchanged at 12 with the same single flip — claims 8-10 are behavioural
//     and contribute no source needles, and claim 7's four moved region-for-region. Measured
//     rather than assumed, because "my new claims are behavioural so the count is the same"
//     is precisely the kind of reasoning this paragraph exists to forbid.
//   · ⭐ RE-MEASURED AGAIN AFTER #743: **TRAGEND (1 of 17)** — claims 11-12 add five needles
//     and the single flip is unchanged. ⚠️ AND THE FIRST MEASUREMENT SAID **3 of 17**, because
//     it counted with `contains` while claims 11-12 test an EXACT TRIMMED LINE. As substrings,
//     `normaliseUnreachableDonutMode()` is 5 raw / 2 stripped and `normaliseDoorlessLeadMix()`
//     4 / 2 — the neighbouring prose discusses them by name. In the form the claims ACTUALLY
//     use, a comment line trims to `// …` and never to the bare call, so all three are immune
//     by construction: 1 raw / 1 stripped each. **Measure a needle in the form its assertion
//     uses.** Counting substrings for a line-equality claim overstated the flip by two — the
//     same error class as measuring a whole file for a claim scoped to one member (#741).
//   · The VERDICT was PROPHYLAKTISCH. Exactly one needle is comment-resident in its own
//     scanned region: `applyPersistedPreset()` occurs TWICE raw inside `configureEQ`'s body
//     and ONCE stripped, because #736 itself put a "⚠️ THE THREE GAINS ARE NOT SET HERE ANY
//     MORE (#736) — applyPersistedPreset() at …" comment there. Delete the real call at
//     the end of that body and leave the comment: claim 4 goes **green raw, red stripped**.
//     The stripper is what keeps the launch path (#714) honest, today, not prophylactically.
//
// ⛔ THAT IS THE FOURTH SLICE RUNNING TO WRITE THIS LABEL FROM INTUITION (#728 flattering,
// #731 the other way, #732 caught by its own run, #736 caught only by review). The old
// paragraph even named the right rule — "count it, do not reason about it" — and then did
// not count. Two things are newly specific and worth carrying:
//   · **Count the needles, not the claims.** Every `contains`/`XCTAssertFalse` needle in the
//     file is a denominator entry, including the ones in counterweights.
//   · **"Driven both ways before pushing" cannot surface this.** For a POSITIVE claim both
//     drives are green today; the flip only appears under a MUTATION. The measurement the
//     rule asks for is a raw-vs-stripped COUNT per needle in its scanned region, which is a
//     dozen lines of Python and takes seconds.
// The stripper also stays for the original reason: claims 3, 4 and 7 read member bodies that
// are half comment by volume.
//
// ⚠️ REGISTERED, MEASURED, NOT BUILT — three gaps the #736 review found that #737 did NOT
// close, because each is new work rather than a false statement. Written here so the next
// session plans from facts instead of rediscovering them:
//   1. ✅ **CLOSED BY #740** — was: no injectable seam, so 5 of 7 claims were text scans.
//      `Preset.resolved(from: UserDefaults)` now exists in the file's own
//      `resolvedTarget(from:)` shape, and `applyPersistedPreset()` calls it.
//   2. ✅ **CLOSED BY #740** — was: nothing asserted the four curves are DISTINCT, so giving
//      all four identical gains stayed green while producing exactly the failure claim 7's
//      message describes. `Preset.gains` is a pure tuple and claims 8 AND 9 compare them
//      (⛔ #740 wrote "claims 8-10"; claim 10 compares stored TOKENS and never reads a curve).
//   3. ✅ **CLOSED BY #743** — was: an unparseable stored value split engine from control.
//      `normaliseUnparseableMasterCharacter()` now rewrites the store at launch, in the same
//      block and the same shape as `normaliseUnreachableDonutMode()` / `normaliseDoorlessLeadMix()`,
//      resolving through `Preset.resolved(from:)` so the fallback stays spelled once.
//      **All three registered items are now closed** — the register is empty, not abandoned.

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

private struct ToneAnchorMissing: Error, CustomStringConvertible {
    let reason: String
    var description: String { "anchor missing: \(reason)" }
}

final class TheMasterToneHasADoorTests: XCTestCase {

    private static let chain = "Sources/Echoelmusic/Audio/AutoMixChain.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"

    // MARK: - 1 · the four characters are selectable and tell themselves apart

    func testAllFourCharactersRoundTripAndReadDistinctly() {
        let all = AutoMixChain.Preset.allCases
        XCTAssertEqual(all.count, 4, """
            `AutoMixChain.Preset` has \(all.count) cases, not 4. The Picker offers whatever
            `allCases` returns, so adding or removing one changes the shipped control — which
            is fine, but the master curve is founder territory (it was retuned from an FFT of a
            real take) and a silent change is not.
            """)
        for p in all {
            XCTAssertEqual(AutoMixChain.Preset(rawValue: p.rawValue), p, """
                `\(p.rawValue)` does not round-trip through its raw value. The raw value is the
                PERSISTENCE token: a case that cannot be parsed back is a stored choice that
                silently reverts to balanced on the next launch.
                """)
        }
        let names = Set(all.map(\.displayName))
        XCTAssertEqual(names.count, all.count, """
            Two characters share a display name, so the Picker shows the same word twice and a
            user cannot tell which one is selected. Display names are deliberately separate
            from raw values — rename the LABEL freely, never the token.
            """)
        for p in all {
            XCTAssertFalse(p.displayName.isEmpty, "\(p.rawValue) has an empty display name")
        }
    }

    // MARK: - 2 · the stored default is a value that actually parses

    func testTheStoredDefaultIsBalancedAndParses() {
        let stored = StudioDefaultKeys.masterCharacter.value
        XCTAssertEqual(AutoMixChain.Preset(rawValue: stored), .balanced, """
            The stored default is "\(stored)", which does not parse to `.balanced`.

            This is the failure a compiler cannot see and a running app cannot show: an
            unparseable default falls back to `.balanced` anyway, so a typo here looks
            IDENTICAL to a working build — until someone renames a case and the fallback
            starts hiding a real stored choice. `.balanced` is also the curve retuned
            2026-06-23 from an FFT of a real take, and it must stay the default.
            """)
    }

    // MARK: - 3 · REGRESSION: the door, and it calls the launch path's own method

    func testTheMasterPanelPicksTheToneThroughTheOneOwner() throws {
        let panel = try memberBody(startingWith: "private var masterPanel", in: Self.studio)
            .joined(separator: "\n")
        XCTAssertTrue(panel.contains("AutoMixChain.Preset.allCases"), """
            The Master panel no longer offers the tonal characters. Before #736 `preset` had no
            writer anywhere in the repository and every session ran `.balanced`; if the control
            moved, move this claim with it, and if it was removed, the doc on
            `AutoMixChain.preset` claims a chooser that does not exist and must be corrected in
            the SAME commit (#456).
            """)
        XCTAssertTrue(panel.contains("audioEngine.autoMixChain.applyPersistedPreset()"), """
            The Picker no longer applies through `applyPersistedPreset()`.

            Mapping the raw value to a `Preset` here instead would be a SECOND owner of the
            same decision: the launch path reads the stored key through that method, so a
            second mapping is how a stored choice and a live tap start disagreeing. This is
            the `MIDIOutput.applyOutputPreferences()` shape and it is the point of the slice.
            """)
    }

    // MARK: - 4 · REGRESSION: the launch path really runs it (#714)

    func testTheGraphBuildAppliesTheStoredCharacter() throws {
        let body = try memberBody(startingWith: "private func configureEQ", in: Self.chain)
            .joined(separator: "\n")
        XCTAssertTrue(body.contains("applyPersistedPreset()"), """
            `configureEQ()` no longer applies the stored character, so a persisted choice does
            not survive a relaunch — the app would start on `.balanced` and the Picker would
            show something else. `configureEQ()` is called from `insert(...)`, which
            `AudioEngine` calls unconditionally while building the graph; that unconditional
            call is the whole reason this is the right place (#714 paid for a launch path that
            "obviously" ran and did not).
            """)
    }

    // MARK: - 5 · REGRESSION (#416): the curve numbers live in exactly one place

    func testTheSetupNoLongerSpellsTheBalancedGainsASecondTime() throws {
        let body = try memberBody(startingWith: "private func configureEQ", in: Self.chain)
            .joined(separator: "\n")
        for band in ["eq.bands[1].gain", "eq.bands[2].gain", "eq.bands[3].gain"] {
            XCTAssertFalse(body.contains(band), """
                `configureEQ()` sets `\(band)` again. Until #736 the `.balanced` gains were
                spelled out twice — here and in `applyPreset()`'s `.balanced` case, the same
                three numbers — so changing one drifted from the other (#416). The gains belong
                to `Preset.gains` (⛔ this message said `applyPreset()` until #741, and #740 is
                the commit that moved them off it — a reader who redded this claim was told to
                put them back where they no longer live); frequency, filter type, bandwidth
                and bypass belong here,
                because those are the same under every character.
                """)
        }
    }

    // MARK: - 6 · COUNTERWEIGHT: the chain is still in the audio graph

    func testTheChainIsStillConstructedAndInserted() throws {
        let code = try codeOf(Self.engine)
        XCTAssertTrue(code.contains("AutoMixChain()"), """
            `AudioEngine` no longer constructs an `AutoMixChain`. Then the Picker moves a
            property on an object nothing owns, and this whole slice guards a control with no
            effect — a different and much larger finding than a missing door.
            """)
        XCTAssertTrue(code.contains("autoMixChain.insert("), """
            The chain is no longer inserted into the audio graph, so its EQ is not on the
            master bus and the four characters cannot be heard whichever one is selected.
            """)
    }

    // MARK: - 8 · the four characters are genuinely DIFFERENT curves

    /// ⭐ THE CLAIM #736 COULD NOT MAKE. Its claim 7 checks that four `case` LABELS appear in
    /// `applyPreset()`'s text — so making all four write the same gains was green while the
    /// Picker silently stopped doing anything. That is a worse state than the doorless one it
    /// replaced, because the operator would believe the master had moved. #740's pure
    /// `Preset.gains` is what makes this assertable at all.
    ///
    /// ⚠️ SCOPE, STATED (#741). It catches an EXACT duplicate and nothing softer. The key is
    /// string-formatted, so `-0.0` and `0.0` — equal as `Float`, identical on the bus — read
    /// as distinct; so does a 0.0001 dB difference, which is inaudible. The failure this
    /// guards ("a Picker entry that changes nothing") has near-miss forms it does not see, and
    /// tightening it would mean choosing an audibility threshold, which is the founder's ear
    /// and not a constant.
    ///
    /// ⚠️ IT ALSO OVERLAPS CLAIM 9: any mutation making a non-transparent character flat reds
    /// BOTH. Claim 9 earns its place on the other direction only — `transparent` ceasing to be
    /// flat — which this claim cannot see. Said here because the header presents claim 9 as
    /// two independent halves and only one of them is.
    func testEveryCharacterIsADistinctCurve() {
        let all = AutoMixChain.Preset.allCases
        var seen: [String: AutoMixChain.Preset] = [:]
        for p in all {
            let g = p.gains
            let key = "\(g.low)|\(g.presence)|\(g.air)"
            if let clash = seen[key] {
                XCTFail("""
                    `\(p.rawValue)` and `\(clash.rawValue)` write the SAME curve \(key).
                    Two names for one sound is a Picker entry that changes nothing — the
                    failure #736's text-scan claim could not see. If two characters really
                    should converge, delete one; do not ship both.
                    """)
            }
            seen[key] = p
        }
    }

    // MARK: - 9 · only Transparent is flat, and it IS flat

    func testTransparentIsTheOnlyFlatCurve() {
        for p in AutoMixChain.Preset.allCases {
            let g = p.gains
            let flat = g.low == 0 && g.presence == 0 && g.air == 0
            XCTAssertEqual(flat, p == .transparent, """
                `\(p.rawValue)` is \(flat ? "flat" : "not flat") and that is the wrong way
                round. Transparent means the master EQ contributes nothing — if it stops being
                flat the name lies; if any OTHER character becomes flat it is an unlabelled
                second Transparent. Both are audible, neither is a compile error.
                """)
        }
        // A sanity rail on the values, and its limits are stated because #740's version
        // claimed more than it checks.
        //   ⛔ "±96 dB" was WRONG: `AVAudioUnitEQFilterParameters.gain` accepts −96…+24 dB,
        //     asymmetric. An unmeasured API range in a comment, in a file whose header spends
        //     two paragraphs on "measure, do not assume".
        //   ⛔ "a typo of one decimal place" has TWO directions and this bound catches ONE.
        //     `5.0 → 50.0` reds; `5.0 → 0.5` is just as much a shipped loudness bug and passes
        //     here AND passes claim 8, since it stays distinct. Read the bound as a rail
        //     against a gross error, never as a check that the curve is right — the shipped
        //     maximum is 5.0, so it carries 2.4× headroom by design.
        //   ⚠️ `isFinite` is a MIRROR on today's code and is labelled as one (#367), the same
        //     treatment claim 1's round-trip gets: `gains` returns four hand-written constant
        //     tuples, so no mutation short of literally typing `.nan` can trip it. It stays as
        //     a forward tripwire for the day these become computed.
        for p in AutoMixChain.Preset.allCases {
            let g = p.gains
            for (name, v) in [("low", g.low), ("presence", g.presence), ("air", g.air)] {
                XCTAssertTrue(v.isFinite && abs(v) <= 12, """
                    `\(p.rawValue)`'s \(name) gain is \(v) dB. A master-bus character that
                    moves a band by more than 12 dB is a mastering error, and a non-finite
                    value would put NaN on the master EQ — the permanent-silence class this
                    repo has shipped before.
                    """)
            }
        }
    }

    // MARK: - 10 · the stored token resolves through ONE pure function

    /// Drives the seam #740 added, against a scratch `UserDefaults` — the first BEHAVIOURAL
    /// coverage of a resolution that had none. The `?? .balanced` fallback is the specific
    /// thing under test: it is what a case RENAME hits, and until now it was reachable only
    /// through a `@MainActor` method that also touches an `AVAudioUnitEQ`.
    func testTheStoredTokenResolvesAndFallsBackToBalanced() throws {
        // `XCTUnwrap`, NOT `XCTSkip` — the house pattern (`SignatureIsThePersonNotTheMoment`,
        // `LeadMixDoorAndNormalisation`). A test host always has a scratch suite; failing to
        // get one is an environment fault, and skipping would hide it behind a green run —
        // the #454 distinction pointing the other way, since nothing here is a missing TREE.
        let suite = "echoel.test.masterCharacter.resolved"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite), """
            No scratch `UserDefaults` suite. Not a finding about the master bus — the host
            could not give this test a sandbox to write in.
            """)
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let key = StudioDefaultKeys.masterCharacter.key
        XCTAssertEqual(AutoMixChain.Preset.resolved(from: defaults), .balanced, """
            A FRESH INSTALL does not resolve to `.balanced`. Nothing calls
            `UserDefaults.register(defaults:)` for this key and `@AppStorage` defaults are
            per-declaration, so `string(forKey:)` returns nil here.

            ⚠️ WHAT THIS PROVES AND WHAT IT DOES NOT (#741). It proves the RESULT. It does not
            prove that the `?? StudioDefaultKeys.masterCharacter.value` step is load-bearing,
            because that value IS "balanced" and the terminal `?? .balanced` lands in the same
            place — revert the seam to `Preset(rawValue: string(forKey:) ?? "")` and this stays
            green. The two `??`s are provably interchangeable TODAY and stop being so the
            moment the canonical default is anything but balanced; claim 2 is what pins that.
            #740's message claimed the first `??` was "doing all the work" — it is doing work
            no assertion can currently see.
            """)

        for p in AutoMixChain.Preset.allCases {
            defaults.set(p.rawValue, forKey: key)
            XCTAssertEqual(AutoMixChain.Preset.resolved(from: defaults), p, """
                A stored `\(p.rawValue)` does not come back as `\(p.rawValue)`. The raw value
                is the PERSISTENCE token — a character that cannot be read back is a choice
                that silently reverts on the next launch.
                """)
        }

        defaults.set("chromatic-mahogany", forKey: key)
        XCTAssertEqual(AutoMixChain.Preset.resolved(from: defaults), .balanced, """
            A stored token that no longer parses does not fall back to `.balanced`. This is
            what a case RENAME produces on an existing install, and `.balanced` is the curve
            retuned 2026-06-23 from an FFT of a real take — the only safe landing.
            """)
    }

    // MARK: - 11 · REGRESSION: an unparseable stored character is rewritten at launch

    /// ⛔ WITHOUT THIS, THE ENGINE AND THE PICKER DISAGREE AND NOTHING CAN FIX IT. The engine
    /// falls back to `.balanced` on its own; the store keeps the unparseable token; the
    /// `@AppStorage`-bound `Picker` finds no matching `.tag(...)` and renders NO selection. The
    /// operator sees a blank control over a master bus that is doing something — and the only
    /// control that could repair the store is the blank one.
    func testTheLaunchPathRewritesAnUnparseableCharacter() throws {
        let code = try codeOf(Self.studio)
        // ⛔ THE NEEDLE IS THE CALL, NOT THE NAME, and the first draft was the name. Measured
        // in the stripped source: `normaliseUnparseableMasterCharacter()` occurs TWICE — the
        // call at launch and the `private func` declaration — so deleting the CALL and leaving
        // a now-dead method would have kept the claim green over exactly the broken state it
        // exists to catch (#367). A call line trims to the bare invocation; a declaration line
        // starts with `private func`. The same trap sits under both siblings (each also occurs
        // twice), which is why this is written as a reusable predicate rather than a needle.
        let calls: [String] = code.components(separatedBy: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .filter({ $0 == "normaliseUnparseableMasterCharacter()" })
        XCTAssertEqual(calls.count, 1, """
            The launch normalisation is not CALLED exactly once (found \(calls.count)).
            `normaliseUnreachableDonutMode()` (#227) and `normaliseDoorlessLeadMix()` (#255)
            are the same shape one store over, and all three exist for one reason: a persisted
            value whose only door cannot show it. Zero calls means the repair is dead code;
            more than one means two launch paths write the store and the later one wins
            silently.
            """)
        let fn = try memberBody(startingWith: "private func normaliseUnparseableMasterCharacter",
                                in: Self.studio).joined(separator: "\n")
        XCTAssertTrue(fn.contains("AutoMixChain.Preset.resolved(from: .standard)"), """
            The normalisation no longer resolves through `Preset.resolved(from:)`.

            Writing `.balanced` (or any literal) here would be a SECOND owner of token →
            character (#416) — the same defect #736 removed from the Picker's `.onChange`, and
            it would silently stop following the day the canonical fallback changes.
            """)
        XCTAssertFalse(fn.contains("applyPersistedPreset()"), """
            The normalisation now re-applies the preset. It must not: the engine already
            resolved the same way while building the graph, so the EQ is correct BEFORE this
            runs. Re-applying makes this a second writer on the audio node for no gain, and
            two writers on one node is how the launch-order bugs in this file started.
            """)
    }

    // MARK: - 12 · COUNTERWEIGHT: the launch block that hosts it is still there

    /// If the whole normalisation block were removed, claim 11's first needle would go red —
    /// but only because the CALL vanished, which reads as "someone deleted my line". This says
    /// the SIBLINGS are the reason the block exists, so a red here names the real event: the
    /// launch-time repair pass itself is gone, and three stores lost their only correction.
    func testTheNormalisationBlockStillCarriesItsSiblings() throws {
        let code = try codeOf(Self.studio)
        for sibling in ["normaliseUnreachableDonutMode()", "normaliseDoorlessLeadMix()"] {
            let called = code.components(separatedBy: "\n")
                .contains(where: { $0.trimmingCharacters(in: .whitespaces) == sibling })
            XCTAssertTrue(called, """
                `\(sibling)` is gone from the launch block. #743 added a third normalisation
                on the strength of those two being the established shape; if the pass itself is
                being retired, this claim and `normaliseUnparseableMasterCharacter()` go with
                it in the same commit (#456) — do not leave one orphan behind.
                """)
        }
    }

    // MARK: - 7 · COUNTERWEIGHT: all four curves still exist

    /// ⛔ THIS CLAIM POINTED AT `applyPreset()` AND #740 MOVED THE BRANCHES OUT OF IT. The
    /// four `case`s now live on `Preset.gains`, and `applyPreset()` is three assignments from
    /// a tuple. Re-anchored in the SAME commit as the move (#456) — a needle left pointing at
    /// a vacated member fails for a reason that has nothing to do with what it guards, and
    /// `dead-needles.py` cannot see it because the FILE still exists.
    ///
    /// ⚠️ It is also WEAKER than it looks now, and that is stated rather than left implied:
    /// claim 8 compares the actual curves, so THIS one only guards the shape of the switch.
    /// It stays because a `default:` collapsing three characters into one branch would go red
    /// here and is the cheapest way to accidentally erase them.
    func testAllFourCurvesStillHaveABranch() throws {
        // ⛔ THE ANCHOR CARRIED EIGHT LEADING SPACES UNTIL #741 AND THEY BOUGHT NOTHING.
        // `var gains:` occurs exactly once in the file, and `memberBody` derives the closing
        // indent from the FOUND line, not from the prefix — so the spaces added only a false
        // FAIL on a pure re-indent or on moving the property into an `extension`, which is the
        // very failure mode #740 was fixing when it re-anchored this claim. It is also the
        // only anchor in this file that carried whitespace; the others do not (#408).
        let body = try memberBody(startingWith: "var gains:", in: Self.chain)
            .joined(separator: "\n")
        for c in ["case .balanced", "case .warm", "case .bright", "case .transparent"] {
            XCTAssertTrue(body.contains(c), """
                `Preset.gains` no longer has a `\(c)` branch — most likely folded into a
                `default:`, which silently gives that character somebody else's curve. Claim 8
                catches an exact duplicate; this catches the branch disappearing.
                """)
        }
    }

    // MARK: - helpers

    /// Lines of a member, from the line containing `prefix` to the closing `}` at that line's
    /// OWN indentation. Structural, not a fixed window (#408). Written with
    /// `components(separatedBy:)` and a plain loop — #726 lost a cycle to a four-stage
    /// inferred chain in exactly this helper.
    private func memberBody(startingWith prefix: String, in path: String) throws -> [String] {
        let lines: [String] = try codeOf(path).components(separatedBy: "\n")
        var start: Int = -1
        for i in 0..<lines.count where lines[i].contains(prefix) {
            start = i
            break
        }
        guard start >= 0 else {
            throw ToneAnchorMissing(reason: """
                `\(prefix)` is gone from \(path). A missing ANCHOR fails rather than skips
                (#454) — a rename would otherwise leave this claim silent about a door that no
                longer exists.
                """)
        }
        let indent: Int = Self.leadingSpaces(lines[start])
        var close: Int = lines.count
        for i in (start + 1)..<lines.count {
            let trimmed: String = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed == "}" && Self.leadingSpaces(lines[i]) == indent {
                close = i
                break
            }
        }
        return Array(lines[(start + 1)..<close])
    }

    private static func leadingSpaces(_ line: String) -> Int {
        var n: Int = 0
        for c in line {
            if c == " " { n += 1 } else { break }
        }
        return n
    }

    private func codeOf(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ToneAnchorMissing(reason: """
                \(relativePath) is not present while `Sources/` is — the anchor moved. A
                missing TREE skips (see `repoRoot`); a missing ANCHOR fails (#454)
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }
}
#endif
