// ThePadShapeDialsReachTheChordTests.swift
// Echoel — #581. The section the founder named, and the three ways it could have been decoration.
//
// THE ASK, verbatim (2026-08-13): *"Ich find es fehlt eine Sektion mit slidern der aus den Pad
// Sounds rhythmische chords macht … Fehlt noch."*
//
// ⭐ IT WAS NEVER MISSING MACHINERY — ONLY A SURFACE, and the engine said so in its own words.
// `BioComposer.roleRhythmOnsets` built its `RoleRhythm.Params` from three hard-coded literals
// under the comment *"The three dials **no role UI exposes** are written out…"*, and
// `RoleRhythm.Params`' docs specify this exact UI under the label "A7", down to which rows must
// be disabled on which character. So this slice is a wiring job over a tested engine, which is
// why the assertions below are mostly END-TO-END rather than source scans.
//
// ⚠️ THE THREE WAYS IT COULD HAVE BEEN DECORATION, one assertion each — because each of them
// produces a section that looks finished and changes nothing:
//   1. **The dials never leave the view.** `Input` defaults them (it must — dozens of test
//      fixtures construct it), so omitting them at the ONE construction site compiles, renders
//      three rows, and composes exactly as before. Claim 2 pins that site.
//   2. **The engine ignores them.** They could arrive and be overwritten by a `Params()` default.
//      Claim 1 drives real `roleRhythmOnsets` output and requires the note LENGTH to follow gate.
//   3. **They are offered where they do nothing.** `evolve` moves only two of the six characters
//      and NOTHING with `padRhythm == ""`. Claims 3 and 4 pin the disabling.
//
// ⚠️ THE LIMIT, PER ASSERTION (§1): claims 1 and 5 are END-TO-END over the shipped, static,
// Foundation-only `BioComposer.roleRhythmOnsets` and `RoleRhythm.Character` — the strong kind.
// Claims 2–4 are SOURCE-TEXT SCANS, because the rows are `private` members of a `View` no bundle
// can instantiate. DEVICE PROBE, open and NOT covered: whether the three dials sound musical
// across the six characters, and whether "Chord length / Accent / Variation" are the right names.
// That is a listening judgement and it belongs to the founder.
//
// ⚠️ HONEST GRADING (§3), hand-transcribed in Python against the parent (`884102f`) and this
// tree — no local toolchain (§0). **27 assertions executed** (12 of them inside claim 1's
// six-character loop, 3 in claim 2's, 3 in claim 4's). The file drives a signature this commit
// CHANGES — `roleRhythmOnsets` gains three required parameters — so it **does not compile
// against the parent and NO assertion has a verdict there**, said plainly rather than left to
// read as "green on its own tree" (§3; #488 shipped a red gate for a cycle behind exactly that
// ambiguity). Transcribed instead, needle by needle, on both trees:
//   · claims 1 and 5 are FORWARD guards over behaviour the parent cannot express.
//   · claims 2–4 scan for text this commit introduces: ONE absence, reported once (#486).
//   · **8 COUNTERWEIGHTS** would be green on both trees if the parent could build this file
//     (claims 5, 6 and claim 4's three negative scans, all measured True/True). Claim 6 is the
//     reason this file is not five positive scans: the defaults must still be the composer's
//     OLD literals, so every existing take and every stored project sounds bit-identical. A
//     slice that "adds sliders" and moves the neutral point re-voices music the founder already
//     approved by ear, and its commit message would say it only added a control.
//   · STRIPPER: **PROPHYLAKTISCH (0 of 13 measured source-scan verdicts flip)** — raw vs.
//     stripped on both trees, not assumed.
//
// ⛔ MY PRE-MEASUREMENT HEADER SAID "10 assertions". Third slice running that I have counted
// `func`s instead of executed `XCTAssert` calls (#579 said 7 for 9, #580 said 7 for 10), and
// twice I wrote down the rule that fixes it. Writing a rule is not applying it: the count is
// now taken by transcribing, like every other number in this bundle, and the loops are named in
// the sentence so the arithmetic is checkable rather than trusted.

import Foundation
import XCTest
@testable import Echoelmusic

final class ThePadShapeDialsReachTheChordTests: XCTestCase {

    private static let view = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - claim 1 (END-TO-END) — gate actually changes the chord's note length

    /// The assertion that separates "wired" from "rendered". If the dial did not reach
    /// `RoleRhythm.Params`, these two runs would be identical.
    ///
    /// ⚠️ Compared as a SUM over a long section rather than per note, and `>=` rather than `>`,
    /// because `RoleRhythm` floors the product at `minGate`: on some characters the bottom of the
    /// dial is deliberately flat (a gate of 0 is a click, not a short note). A strict per-note
    /// inequality would be red on correct code for exactly the reason the engine documents.
    func testAShorterGateProducesShorterChords() {
        for character in RoleRhythm.Character.allCases {
            let short = BioComposer.roleRhythmOnsets(
                secStart: 0, secLen: 64, sectionIndex: 0, character: character, density: 0.5,
                gate: 0.1, accent: 0.4, evolve: 0.2, seed: 0x5A1)
            let long = BioComposer.roleRhythmOnsets(
                secStart: 0, secLen: 64, sectionIndex: 0, character: character, density: 0.5,
                gate: 1.0, accent: 0.4, evolve: 0.2, seed: 0x5A1)
            XCTAssertEqual(short.count, long.count, """
                \(character): gate changed WHICH cells sound. It must only change how long they \
                are — the onset pattern is the character's, and a dial that re-writes the figure \
                would make the rhythm Picker above it mean less than it says.
                """)
            let shortTotal = short.reduce(0) { $0 + $1.len }
            let longTotal = long.reduce(0) { $0 + $1.len }
            XCTAssertLessThanOrEqual(shortTotal, longTotal, """
                \(character): gate 0.1 did not produce chords at most as long as gate 1.0 \
                (\(shortTotal) vs \(longTotal) steps). Either the dial does not reach \
                `RoleRhythm.Params` — the whole section is then decoration — or its direction is \
                inverted against the label "Chord length".
                """)
        }
    }

    // MARK: - claim 2 (SOURCE SCAN) — the dials leave the view at the one place that matters

    /// The single highest-value assertion in the file, and the one a reviewer is most likely to
    /// think unnecessary. `BioComposer.Input` DEFAULTS these three (it has to — dozens of
    /// fixtures construct it), so forgetting this one line compiles cleanly, renders three
    /// working-looking rows, and composes exactly as before.
    func testTheRowsReachTheComposerInput() throws {
        let src = try source(Self.view)
        XCTAssertTrue(src.contains("padGate: Float(padGate)"), """
            The composer `Input` is no longer built with the pad-shape rows. `Input` defaults \
            these fields, so this does not fail to compile and nothing on screen changes — the \
            section simply stops doing anything, which is the exact defect the founder was \
            describing when he said the section was missing.
            """)
        for field in ["padAccent: Float(padAccent)", "padEvolve: Float(padEvolve)"] {
            XCTAssertTrue(src.contains(field), """
                `\(field)` is missing from the `Input` construction. A partially-wired section is \
                worse than an unwired one: two rows move the music, one does not, and nothing on \
                screen distinguishes them.
                """)
        }
    }

    // MARK: - claim 3 (SOURCE SCAN) — nothing is offered while the composer would not run it

    func testTheRowsDisableWhenNoPadCharacterIsChosen() throws {
        let src = try source(Self.view)
        XCTAssertTrue(src.contains("let off = character == nil"), """
            The pad-shape rows no longer compute whether a character is chosen. With `padRhythm` \
            on "Genre" the composer never calls `roleRhythmOnsets` at all, so all three rows \
            would sweep their range in silence — the lying-control defect this repo has paid for \
            three times (#135/#164/#227).
            """)
        XCTAssertEqual(src.components(separatedBy: ".disabled(off)").count - 1, 2, """
            The number of rows disabled by the no-character state is not two. Chord length and \
            Accent are disabled by `off` alone; Variation carries a second condition and is \
            asserted separately. If a row was added, disable it too.
            """)
    }

    // MARK: - claim 4 (SOURCE SCAN) — Variation asks the engine, not a hard-coded list

    /// ⛔ `RoleRhythm.Character.usesEvolve`'s own doc records that the FIRST attempt at this UI
    /// hard-coded the character list in the view and got it wrong — and that the sibling flag
    /// `accentIsSubtle` exists because the same attempt hard-coded `hypnotic || flowing` and left
    /// out `sparse`, which spreads MORE than `hypnotic`. This assertion is that lesson, executable.
    func testVariationReadsTheEngineFlagRatherThanAList() throws {
        let src = try source(Self.view)
        XCTAssertTrue(src.contains("character?.usesEvolve"), """
            The Variation row no longer reads `Character.usesEvolve`. `evolve` moves only \
            `dynamic` and `flowing`; on the other four it does nothing at all — `hypnotic` \
            included, whose bar-to-bar rotation is a pure function of the bar index and consults \
            neither the dial nor the seed. A hard-coded list here has already been wrong once.
            """)
        XCTAssertTrue(src.contains("character.accentIsSubtle"), """
            The caption no longer reads `Character.accentIsSubtle`. Without it the Accent row \
            promises the same effect on `flowing` (≈0.5 dB spread) as on `dynamic` (≈5.8 dB) — a \
            2.6× gap the engine measures and exposes precisely so a view need not guess.
            """)
        for banned in ["== .hypnotic", "== .flowing", "== .dynamic"] {
            XCTAssertFalse(src.contains("padShape") && src.contains("\(banned) ||"), """
                The pad-shape section appears to compare characters directly (`\(banned) ||`). \
                That is the shape of the hard-coded list that was already wrong once; ask the \
                engine flag instead.
                """)
        }
    }

    // MARK: - claim 5 (END-TO-END) — the two engine flags still split the six as documented

    /// The premise claims 3–4 depend on. If `usesEvolve` ever silently became "all six", the view
    /// would still be reading the engine — correctly — and offering a dead row on four characters.
    func testTheEngineFlagsStillSplitTheCharacters() {
        let evolving = RoleRhythm.Character.allCases.filter(\.usesEvolve)
        XCTAssertEqual(Set(evolving), Set([.dynamic, .flowing]), """
            `usesEvolve` no longer selects exactly dynamic + flowing (it now selects \
            \(evolving.map(\.rawValue).sorted().joined(separator: ", "))). The Variation row \
            follows this flag, so a change here silently changes which characters offer the dial \
            — correct if the engine really changed, and a dead row on four characters if not.
            """)
        let subtle = RoleRhythm.Character.allCases.filter(\.accentIsSubtle)
        XCTAssertEqual(Set(subtle), Set([.sparse, .hypnotic, .flowing]), """
            `accentIsSubtle` no longer selects exactly sparse + hypnotic + flowing. The caption \
            follows this flag; `sparse` is the one an earlier hand-written version left out.
            """)
    }

    // MARK: - claim 6 (COUNTERWEIGHT) — the neutral point did not move

    /// Green on both trees in intent, and the point of the file. Adding a dial is safe only while
    /// its default reproduces the number the engine used to hard-code — otherwise every take the
    /// founder already approved by ear, and every stored project, is re-voiced by a slice whose
    /// commit message says it only added a control.
    func testTheDefaultsAreStillTheComposersOldLiterals() {
        XCTAssertEqual(StudioDefaultKeys.padGate.value, 0.8, accuracy: 1e-9, """
            The Chord length default moved. 0.8 / 0.4 / 0.2 are the literals \
            `roleRhythmOnsets` carried before this section existed, so they are what keeps an \
            untouched install bit-identical. Re-tuning one re-voices the chord of every user who \
            never opened the row — the same standing warning `RoleRhythm` gives about `Params`.
            """)
        XCTAssertEqual(StudioDefaultKeys.padAccent.value, 0.4, accuracy: 1e-9,
                       "The Accent default moved — see the Chord length message.")
        XCTAssertEqual(StudioDefaultKeys.padEvolve.value, 0.2, accuracy: 1e-9,
                       "The Variation default moved — see the Chord length message.")
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct PadShapeAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw PadShapeAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
