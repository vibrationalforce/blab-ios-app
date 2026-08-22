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
// ⚠️ LABELLED "Tone", NOT "Character", and that is deliberate: `EchoelStudioView` already has
// two `labeledRow("Character")` rows — the sound preset row and the Effects picker. A third
// meaning of one word in one app is worse than a longer label.
//
// LIMITS, STATED FIRST (§1). Claims 1-2 are END-TO-END BEHAVIOUR over shipped value types.
// Claims 3-7 are a SOURCE-TEXT SCAN: `AutoMixChain` is `@MainActor` and owns an
// `AVAudioUnitEQ`, and `masterPanel`'s members are `private` on a `View`, so neither can be
// driven here. That the four curves SOUND different, and that Warm actually reads warm, is a
// DEVICE PROBE and stays open — it is also the only thing that matters to the founder's ear.
//
// ⚠️ HONEST GRADING (#433/#464/#486). This file names `AutoMixChain.Preset.allCases` and
// `StudioDefaultKeys.masterCharacter`, both created by THIS commit, so it **does not compile
// against the parent `e837ccb` and no assertion has a verdict there** (#488 shipped a red gate
// for a cycle behind exactly that ambiguity). Hand-transcribed in Python against both trees:
//   · Claims 1-2 are FORWARD guards (#433) — they drive symbols this commit adds and could
//     never have been red. What earns them a place is that they check the two failure modes a
//     compiler cannot: a stored default that does not PARSE (silently identical to a working
//     one), and two characters sharing a display name.
//   · Claims 3-5 are REGRESSIONS: the parent has no Picker, no launch call, and spells the
//     `.balanced` gains twice. Counted as ONE finding — the door's absence (#486).
//   · Claims 6-7 are COUNTERWEIGHTS, green on both. Without them, deleting the chain from the
//     graph or collapsing `applyPreset()` to one case would leave the door green over a
//     control that moves nothing.
//
// ⚠️ STRIPPER (#453/#477): **PROPHYLAKTISCH (0 of 3)**, measured — and the first draft of
// this paragraph said `TRAGEND (1 of 3)` on the reasoning that claim 5's negative needle
// would be satisfied by the comment this commit put there. It is not: that comment writes
// "the three gains" and `eq.bands[N].gain` in prose, never the literal `eq.bands[1].gain`,
// so the needle is absent raw AND stripped. Driven both ways before pushing.
//
// ⛔ THAT IS THE THIRD SLICE RUNNING TO WRITE THIS LABEL FROM INTUITION (#728 in the
// flattering direction, #731 in the other, #732 caught by its own run). The pattern is
// specific enough to name: a NEGATIVE claim feels stripper-dependent because a comment
// nearby discusses the thing — but the needle is a literal, and prose about a literal is not
// the literal. **Count it, do not reason about it.** The stripper stays because claims 3, 4
// and 7 read member bodies that are half comment by volume, and a needle shortened by a
// later slice would inherit a real flip.

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

    // MARK: - 7 · COUNTERWEIGHT: all four curves still exist

    func testAllFourCurvesStillHaveABranch() throws {
        let body = try memberBody(startingWith: "private func applyPreset", in: Self.chain)
            .joined(separator: "\n")
        for c in ["case .balanced", "case .warm", "case .bright", "case .transparent"] {
            XCTAssertTrue(body.contains(c), """
                `applyPreset()` no longer has a `\(c)` branch, so the Picker offers a character
                that changes nothing — worse than the doorless state it replaced, because the
                operator would believe the master had moved.
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
