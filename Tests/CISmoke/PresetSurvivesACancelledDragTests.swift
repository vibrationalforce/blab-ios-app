// PresetSurvivesACancelledDragTests.swift
// Echoel — the visual Preset chip is persisted state, so clearing it needs a way back.
//
// WHAT THIS GUARDS (#379). `visualPresetID` is `@AppStorage("visual.preset")` — the NAME of the
// visual scene the user picked. A cancelled drag on any energy row used to clear it, so the
// preset strip read "nothing selected" over values that were exactly that preset's. A control
// that denies the state it is showing is the lying-control class this repo removed in #135/#164.
//
// The shape of the bug is what makes it worth a guard. #376–#378 taught `EchoelValueField` to
// put a value back when a drag is cancelled — a scroll stealing the gesture, a finger leaving
// the screen. That fixed the NUMBER and, in doing so, removed the only SYMPTOM of the preset
// loss: before, the numbers stayed visibly moved; now they read exactly as before while the
// selection is gone. A silent loss is strictly worse than a visible one.
//
// ⛔ THIS HEADER USED TO SAY SOMETHING FALSE, AND IT WAS THE FILE'S STATED REASON TO EXIST:
// that `visualPresetID` is the only visual state surviving a relaunch, "the four energy values
// are not persisted individually". They ARE — `visualIntensity`/`visualDetail`/`visualMotion`/
// `visualSpread` are `@AppStorage` in `EchoelStudioView` (keys `StudioDefaultKeys.visual*`), and
// they must be, because `FloatingVisualWindow` and `ExternalDisplayScene` read the same four
// keys. A relaunch restores the PICTURE either way. The #379 reviewer found it one commit after
// it shipped, in six places at once. Kept as a retraction rather than a silent edit: the bug is
// real and the fix is unchanged, only its severity was overstated.
//
// ⚠️ SCOPE, TWICE OVER. (1) These tests scan ONE file. A second writer of two of the four keys
// exists — `VisualMoodPadLeaf` in `MoodPads.swift` writes `visual.motion`/`visual.intensity`
// without touching the chip — and is invisible here. It is parked (its only mount is a known
// orphan), so today that is a latent lie, not a live one. (2) Of the five callers of
// `visualPresetDiverged()`, the restore can only work for FOUR: the Energy macro binds a derived
// value, so a cancelled drag there restores the dial position rather than the preset's pair.
// The reason is written at `visualPresetDiverged` itself.
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
            An `EchoelValueField` row clears `visualPresetID` directly again. A cancelled drag \
            (scroll steal, finger off-screen) then puts the NUMBER back while the chip stays \
            unselected — a strip that denies the state it is showing. Route the row through \
            `visualPresetDiverged()`, which remembers what it cleared and restores it when the \
            values come back.
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

    /// The comparison itself must still BE a comparison. Without this, replacing
    /// `sameOnDisplayGrid`'s body with `true` leaves all the other assertions green while the
    /// chip is restored on ANY energy edit — the lying control the test above names. The four
    /// needles pin the call SHAPE; this one pins what the call does.
    ///
    /// The rounding is the design, not an implementation detail: a preset writes `Double(Float)`
    /// (Aura's intensity lands on 0.800000011920929) while every path through
    /// `EchoelValueField.apply` snaps to the 4-decimal display grid. Raw `==` would restore after
    /// a cancelled drag but never after the same number was typed back in.
    func testTheComparisonActuallyCompares() throws {
        let squashed = try squashedCode(Self.studio)
        XCTAssertTrue(squashed.contains("(a*10_000).rounded()==(b*10_000).rounded()"), """
            `sameOnDisplayGrid` no longer rounds both sides onto the 4-decimal display grid. If \
            it was widened (or replaced by something always-true) the chip comes back on edits \
            that moved the picture away from the preset; if it was narrowed to raw `==`, the \
            cancelled-drag case it exists for stops working for every preset whose value is a \
            `Double(Float)`. Found by the #379 reviewer: the other five tests here stay green \
            through both changes.
            """)
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

    /// The memo must NOT be persisted. It is scoped to a single edit chain; one that outlived a
    /// launch would put a chip back onto values the user may have changed in between — a
    /// selection nobody made. (The FIRST version of this reason was the false-premise one: "a
    /// selection whose values `onAppear` never re-applied". `onAppear` re-applies nothing the
    /// four `@AppStorage` keys have not already restored. Same conclusion, honest reason.)
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
            `clearedVisualPresetID` became persisted. It must not survive a launch: the memo \
            is scoped to ONE edit chain, and one restored from disk would put a chip back onto \
            values the user may have changed in between. Declaration was: \(decl)
            """)
    }

    // MARK: - The launch may not write through the preset (#1032)

    /// ⭐ Claim 8 — THE LAUNCH CLOSURE MUST NOT RE-APPLY THE PERSISTED PRESET.
    ///
    /// Until #1032 the launch ran `if !visualPresetID.isEmpty, let p = …first { applyVisualPreset(p) }`
    /// under a comment claiming it restored state that "isn't persisted individually". Measured,
    /// that premise is false: all six values `applyVisualPreset` writes are `@AppStorage`. So the
    /// block could only OVERWRITE, and what it overwrote was the player's own later edits —
    /// permanently, because Hue and Saturation deliberately do not call `visualPresetDiverged()`
    /// (their rows say so), leaving `visualPresetID` on "vapor" while the picture was no longer
    /// Vapor. Dialling Hue to 0 for the physical tone→light colour survived exactly until the
    /// next launch, and no control could stop it.
    ///
    /// ⚠️ THIS IS A NEGATIVE CLAIM, so it carries its counterweight (#367): the ONE surviving
    /// caller — the preset chip in `visualPresetRow` — must still be there. Without that half a
    /// rename of `applyVisualPreset`, or its deletion outright, would satisfy the absence and
    /// report a green where tapping a preset does nothing at all.
    ///
    /// ⚠️ `SourceText.codeOnly` IS ONLY PROPHYLACTIC HERE, and this note is the second draft.
    /// ⛔ The first said the stripping was load-bearing — that raw text would match the quote in
    /// #1032's retraction at the removal site and report the defect still present. Measured on
    /// this tree with the real squash: raw and stripped BOTH miss it, because the retraction
    /// quotes the line with an ellipsis (`…factory.first`) and the needle wants
    /// `letp=VisualPreset.factory` unbroken. The dependency is real but dormant; it wakes the
    /// day somebody quotes the deleted line verbatim. Same lesson this bundle already wrote
    /// down once (`VisualFineTuneReflowsTests`, claim 6): a rationale that upgrades a guard's
    /// dependency is a claim like any other and needs the same one command.
    ///
    /// #364: if a launch-time apply is ever genuinely needed again (say a preset gains a value
    /// that is NOT persisted), this claim is the place to say why — re-anchor it with that
    /// reason, do not delete it silently.
    func testTheLaunchDoesNotReApplyThePersistedPreset() throws {
        let squashed = try squashedCode(Self.studio)
        XCTAssertFalse(squashed.contains(#"if!visualPresetID.isEmpty,letp=VisualPreset.factory"#), """
            The launch closure re-applies the persisted preset again (#1032).

            Every value `applyVisualPreset` writes is already `@AppStorage`, so this restores \
            nothing and can only overwrite. It reverts the player's own Hue/Saturation at every \
            start — those two rows do not clear `visualPresetID`, so the stale id keeps pointing \
            at a preset the picture left long ago. That is the defect behind the founder's ask \
            for physically correct colour: the Hue dial works, the launch undid it.

            If a preset ever gains a value that genuinely does NOT persist, restore ONLY that \
            value here and say which one — never the whole preset.
            """)
        XCTAssertTrue(squashed.contains("}else{applyVisualPreset(preset)}"), """
            `applyVisualPreset` has lost its one remaining caller, the preset chip in \
            `visualPresetRow`. The assertion above would then pass on an app where tapping a \
            preset does nothing — a green built on absence (#367). Re-anchor both halves \
            together on whatever replaced the chip.
            """)
    }

}
