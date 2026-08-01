// PresetSurvivesACancelledDragTests.swift
// Echoel — the visual Preset chip is persisted state, so clearing it needs a way back.
//
// WHAT THIS GUARDS (#379). `visualPresetID` is `@AppStorage("visual.preset")` and it is the
// ONLY visual state that survives a relaunch: the four energy values (Intensity · Detail ·
// Motion · Spread) are not persisted individually, and `onAppear` restores the picture by
// re-applying the NAMED preset. So every path that writes `visualPresetID = ""` is throwing
// away a performance/installation setup, not a highlight.
//
// The shape of the bug is what makes it worth a guard. #376–#378 taught `EchoelValueField` to
// put a value back when a drag is cancelled — a scroll stealing the gesture, a finger leaving
// the screen. That fixed the NUMBER and, in doing so, removed the only SYMPTOM of the preset
// loss: before, the numbers stayed visibly moved; now they read exactly as before while the
// persisted selection is gone. A silent loss is strictly worse than a visible one.
//
// The fix lives in the OWNER (`EchoelStudioView`), not in `EchoelValueField` — the field has
// 62 call sites and no business knowing what a preset is. `visualPresetDiverged()` clears the
// chip and remembers what it cleared; if a later write lands the four values back on that
// preset's numbers, it puts the chip back.
//
// ⚠️ SOURCE-TEXT SCAN, and the limit is the same one every guard in this bundle carries. There
// is no simulator here and the blocking bundle is `Tests/CISmoke`, so no gesture can be run and
// no `@AppStorage` round-trip observed. A green here means the rule is still SPELLED. What it
// genuinely catches is the realistic regression: someone adding a fifth energy row, or a fifth
// writer of `visualPresetID = ""`, without the memo — which is exactly how the four rows got
// there in the first place.
//
// ⚠️ IT SKIPS rather than passes when the source tree is not at the compiled-from path. A green
// on an unscanned tree is the `continue-on-error` lie the `doctor` skill exists to catch.
//
// ⛔ MATCHED ON COMMENT-STRIPPED SOURCE. The blocks pinned below are surrounded by prose that
// quotes the very spellings being checked, and the sibling `ScrubNotifiesOnlyOnRealChangeTests`
// paid for the other half of this: squashing raw source keeps inline comments inside a pinned
// block, so an explanatory line added mid-block reddens the gate for prose. Whole-line comments
// are dropped here BEFORE squashing; keep explanations on their own lines, above the code.

import Foundation
import XCTest

final class PresetSurvivesACancelledDragTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…` → up two).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // repo
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// The same lines with ALL whitespace removed, so reformatting cannot redden the gate.
    private func squashedCode(_ path: String) throws -> String {
        try codeLines(path)
            .map { $0.components(separatedBy: .whitespacesAndNewlines).joined() }
            .joined()
    }

    // MARK: - Every energy row goes through the memo

    /// The four fine-tune rows and the Energy macro must all call `visualPresetDiverged()`.
    /// A bare `visualPresetID = ""` on any of them is the #379 defect back: it clears the
    /// persisted selection with nothing recording what was cleared, so the revert that
    /// #378 performs on a cancelled drag has nothing to restore.
    func testNoEnergyRowClearsThePresetWithoutTheMemo() throws {
        let squashed = try squashedCode(Self.studio)
        XCTAssertFalse(squashed.contains(#"onChange:{visualPresetID=""}"#), """
            An `EchoelValueField` row clears `visualPresetID` directly again. That key is \
            `@AppStorage` and is the ONLY visual state `onAppear` restores, so a cancelled \
            drag (scroll steal, finger off-screen) now puts the NUMBER back while the \
            persisted look is silently gone. Route the row through `visualPresetDiverged()`, \
            which remembers what it cleared and restores it when the values come back.
            """)

        let calls = try codeLines(Self.studio).filter {
            $0.contains("visualPresetDiverged()") && !$0.contains("private func")
        }
        XCTAssertEqual(calls.count, 5, """
            Expected 5 calls to `visualPresetDiverged()` — the four fine-tune rows \
            (Intensity · Detail · Motion · Spread) plus the Energy macro binding that writes \
            two of them — and found \(calls.count). A NEW energy control was added without \
            the memo, or one was removed. Hue and Saturation deliberately do not call it: \
            they are palette-only and leave the selection intact. Lines found:
            \(calls.joined(separator: "\n"))
            """)
    }

    /// Only TWO places may write the empty string into `visualPresetID`: the memo function
    /// itself, and the deliberate deselect (tapping the active chip). A third is a loss with
    /// no way back.
    func testOnlyTwoPlacesClearThePresetKey() throws {
        let bare = try codeLines(Self.studio).filter {
            $0.trimmingCharacters(in: .whitespaces) == #"visualPresetID = """#
        }
        XCTAssertEqual(bare.count, 2, """
            Expected exactly 2 bare clears of `visualPresetID` — one inside \
            `visualPresetDiverged()` (which takes the memo first) and one in \
            `visualPresetRow`'s deselect branch (the user's own, which forgets the memo on \
            purpose) — and found \(bare.count). Any other writer drops persisted state with \
            nothing recording it.
            """)
    }

    // MARK: - The memo is taken, given back, and forgotten in the right places

    /// The clear-then-try-restore order is the whole design: taking the memo BEFORE clearing
    /// makes a write that moved nothing a provable no-op (memo taken, memo returned), which is
    /// the case `visualEnergy`'s old `if changed` guard covered on its own.
    func testTheMemoIsTakenBeforeTheClearAndReturnedAfterAMatch() throws {
        let squashed = try squashedCode(Self.studio)
        XCTAssertTrue(
            squashed.contains(#"if!visualPresetID.isEmpty{clearedVisualPresetID=visualPresetID}visualPresetID="""#),
            """
            `visualPresetDiverged()` no longer takes the memo before clearing. If the clear \
            happens first, or the memo is only written when the value actually moved, a \
            cancelled drag has nothing to restore — which is precisely #379.
            """)
        XCTAssertTrue(squashed.contains(#"visualPresetID=clearedVisualPresetIDclearedVisualPresetID="""#), """
            The restore is gone: nothing puts `clearedVisualPresetID` back into \
            `visualPresetID` (and clears the memo afterwards). Without it the function is a \
            plain clear again and the persisted look stays lost after a cancelled drag.
            """)
    }

    /// All four energy values must agree before the chip comes back. Restoring on a subset
    /// would name a preset the picture no longer matches — the lying-control class this repo
    /// has removed twice (#164, #135).
    func testTheRestoreComparesAllFourEnergyValues() throws {
        let squashed = try squashedCode(Self.studio)
        let pairs = [("visualIntensity", "p.intensity"), ("visualDetail", "p.detail"),
                     ("visualMotion", "p.motion"), ("visualSpread", "p.spread")]
        for (live, preset) in pairs {
            XCTAssertTrue(squashed.contains("sameOnDisplayGrid(\(live),Double(\(preset)))"), """
                The restore no longer compares \(live) against \(preset). All four energy \
                values a preset owns must match before the chip is put back, or the strip \
                would claim a preset that is not on screen.
                """)
        }
    }

    /// Two deliberate forgets. A fresh pick has nothing to restore, and a user's own deselect
    /// must not be undoable by the next cancelled drag.
    func testTheMemoIsForgottenOnAFreshPickAndOnADeliberateDeselect() throws {
        let squashed = try squashedCode(Self.studio)
        XCTAssertTrue(squashed.contains(#"visualPresetID=p.idclearedVisualPresetID="""#), """
            `applyVisualPreset` no longer forgets the memo. Tapping a new preset while an \
            earlier one is still remembered would let a later cancelled drag resurrect the \
            PREVIOUS chip over the one just chosen.
            """)
        XCTAssertTrue(
            squashed.contains(#"ifselected{visualPresetID=""clearedVisualPresetID=""}else{applyVisualPreset(preset)}"#),
            """
            The deselect branch in `visualPresetRow` no longer clears the memo alongside the \
            key. `visualPresetDiverged()` restores what IT cleared; a deselect is the user's \
            own decision and must stay cleared, or the next cancelled drag undoes it.
            """)
    }

    /// The memo must NOT be persisted. It only has to survive one edit chain; a memo that
    /// outlived a launch would restore a selection whose values `onAppear` never re-applied,
    /// so the chip would name a look that is not on screen.
    func testTheMemoIsViewStateAndNotPersisted() throws {
        let lines = try codeLines(Self.studio).filter { $0.contains("var clearedVisualPresetID") }
        XCTAssertEqual(lines.count, 1, """
            Expected exactly one declaration of `clearedVisualPresetID`, found \(lines.count).
            """)
        let decl = lines.first ?? ""
        XCTAssertTrue(decl.contains("@State"), """
            `clearedVisualPresetID` is no longer `@State`. Declaration was: \(decl)
            """)
        XCTAssertFalse(decl.contains("@AppStorage"), """
            `clearedVisualPresetID` became persisted. It must not survive a launch: \
            `onAppear` re-applies only the NAMED preset, so a memo restored from disk would \
            put a chip back over values nothing had restored. Declaration was: \(decl)
            """)
    }
}
