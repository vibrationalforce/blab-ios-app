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
// ⚠️ HONEST GRADING (#433/#464/#486). This file names `AutoMixChain.Preset.allCases` and
// `StudioDefaultKeys.masterCharacter`, both created by THIS commit, so it **does not compile
// against the parent `e837ccb` and no assertion has a verdict there** (#488 shipped a red gate
// for a cycle behind exactly that ambiguity). Hand-transcribed in Python against both trees:
//   · Claims 1-2 are FORWARD guards (#433) — they drive symbols this commit adds and could
//     never have been red. What earns them a place is that they check the two failure modes a
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
//   · Claims 3-5 are REGRESSIONS: the parent has no Picker, no launch call, and spells the
//     `.balanced` gains twice. Counted as ONE finding — the door's absence (#486).
//   · Claim 6 is a COUNTERWEIGHT, green on both. Without it, deleting the chain from the
//     graph would leave the door green over a control that moves nothing.
//   · Claim 7 is re-anchored by #740 and is ANCHOR-ABSENT on `c2895c8` (the branches lived in
//     `applyPreset()` there, not on `Preset.gains`) — a FAIL, not a skip, which is the right
//     reading per #454 since the FILE exists and only the member moved.
//   · Claims 8-10 are FORWARD (#433): they name `Preset.gains` and `Preset.resolved(from:)`,
//     both created by #740, so they do not compile against the parent and have no verdict
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
//      message describes. `Preset.gains` is a pure tuple and claims 8-10 compare them.
//   3. **AN UNPARSEABLE STORED VALUE SPLITS ENGINE FROM CONTROL.** `applyPersistedPreset()`
//      falls back to `.balanced` in the ENGINE, but nothing normalises the stored key, so
//      `@AppStorage` would still hold a raw value matching no `.tag(...)` and a SwiftUI
//      `Picker` with an unmatched selection shows NOTHING selected. Engine plays Balanced,
//      control reads blank — which contradicts this file's own "a persisted choice and a live
//      tap cannot disagree". Only reachable after a case RENAME, and claim 2 is the tripwire
//      for that, so it is a corner. The repair has a precedent in the very same view:
//      `normaliseUnreachableDonutMode()`.

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
                to `applyPreset()`; frequency, filter type, bandwidth and bypass belong here,
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
        // Every gain must stay inside what an AVAudioUnitEQ band accepts (±96 dB), and well
        // inside what a master bus should ever do. A typo of one decimal place here is a
        // shipped loudness bug, not a rounding difference.
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
            per-declaration, so `string(forKey:)` returns nil here and the canonical
            fresh-install value in `StudioDefaultKeys` is doing all the work.
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
        let body = try memberBody(startingWith: "        var gains:", in: Self.chain)
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
