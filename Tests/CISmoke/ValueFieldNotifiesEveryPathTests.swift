// ValueFieldNotifiesEveryPathTests.swift
// Echoel — every way of changing a value must notify the same way. BLOCKING bundle.
//
// `EchoelValueField` is THE numeric control — the whole rule that Echoel has no raw `Slider`.
// (This line said "58 call sites" until #375. That number is not one the repo ever measured:
// `Core/EchoelDecimalText.swift` carries the counted figure next to its command and strikes "58"
// by name. Read it there; do not re-copy a number here, because nothing asserts it.)
// It offers three ways to change a value:
//
//   1. DRAG the box (fader) — `onChange()` per event, `onCommit()` on end.
//   2. TAP to type on the `EchoelNumberPad` — `onChange()` then `onCommit()`, once.
//   3. VOICEOVER swipe up/down (`accessibilityAdjustableAction`).
//
// ⛔ THE DEFECT (found 2026-07-29). Path 3 called only `onCommit()`. That is not a smaller
// version of the same notification — the two callbacks do different jobs, and `apply(_:)` itself
// does neither. `apply` writes the binding and (since #375) reports whether the value MOVED; the
// WORK is in the caller's closures. `onChange` is live-apply — 10 argument sites, 8 of them a
// rendered row and 2 the `param`/`knob` helpers, which render 17 more, so 25 rows carry one;
// `onCommit` is persist/settle (4 sites).
//
// ⛔ THOSE READ "7 … ~22 … 3" UNTIL #375, AND ALL THREE WERE WRONG. The counts:
//   git grep -n "onChange:" -- 'Sources/**/*.swift'   → 10 sites (2 declarations + 1
//       `SignalRouter.onChange` + 1 prose line are NOT sites)
//   git grep -n "onCommit:" -- 'Sources/**/*.swift'   → 4 sites (5 further hits are declarations)
//   grep -c 'param("' / 'knob("' EchoelStudioView.swift → 4 + 13 = 17 helper-rendered rows
// The "~22" in particular was never measured — it was inherited verbatim through two rewrites of
// the sibling comment in `EchoelValueField.swift`, which is the whole reason this block now
// carries its commands. Re-run them; do not quote these numbers bare.
//
// So a VoiceOver user adjusting the timbre heard the number change and heard the instrument NOT
// change. The patch editor behind the Sound chip is ship-gate item 2 — "Kontrolle" — and for a
// non-sighted performer it was reachable and inert. Nothing threw, nothing logged, and the
// spoken value was always correct, which is precisely why it survived.
//
// ⚠️ A SECOND DEFECT ON THE SAME PATH, found in review of the fix above and shipped with it: the
// step was `span / 50` regardless of `decimals`. `apply` snaps to the `10^decimals` grid, so any
// `decimals: 0` field with a span under 25 rounded straight back and could not be adjusted AT
// ALL — "Beats per bar" (1…12), the Field's "Voices" (1…8), FX "Bits" (1…16), both Harmonizer
// intervals (−12…12). Wiring the callback alone would have cured the silence and left the
// paralysis, on a control whose hint says "Swipe up or down to adjust".
//
// ⚠️ ONE OF THOSE FOUR IS NOW HISTORY, and is kept below deliberately. The two Harmonizer
// intervals became a NAMED-interval `Picker` later the same day (founder: *"keine semitone
// Schritte sondern sinnvolle harmonische"*), so they are no longer `EchoelValueField`s at all.
// The table entry stays because it is a real shipped range that this arithmetic froze — it
// documents the defect's reach, not the app's present controls.
//
// WHY A SOURCE SCAN. The action closure is attached to a SwiftUI `View` body; there is no seam to
// invoke it from a unit test and no local toolchain to build a UI-test host with. A real test
// would be an XCUITest driving VoiceOver, which this repo has no runner for. So the guard is
// text — bounded to the closure so the many legitimate `onChange()` calls elsewhere in the file
// cannot make it pass vacuously.
//
// WHAT THIS CANNOT PROVE: that VoiceOver actually reaches the field, that the step size is
// usable, or that the spoken value is right. It proves only that the adjustment is wired to the
// same two callbacks the sighted paths use.

import Foundation
import XCTest
@testable import Echoelmusic

final class ValueFieldNotifiesEveryPathTests: XCTestCase {

    private static let field = "Sources/Echoelmusic/Studio/EchoelValueField.swift"

    /// ⛔ THE GUARD. The VoiceOver adjustment must call BOTH callbacks, because the sighted
    /// paths do and because `onChange` is the only one that reaches the engine.
    func testTheVoiceOverAdjustmentCallsBothCallbacks() throws {
        let closure = try closureBody(after: ".accessibilityAdjustableAction {", in: Self.field)

        XCTAssertTrue(closure.contains("onChange()"),
                      "The VoiceOver adjustment does not call `onChange()`, so it moves the "
                      + "number without applying it — the timbre editor becomes reachable and "
                      + "inert for a non-sighted performer (ship-gate 2). Closure was:\n"
                      + closure)
        XCTAssertTrue(closure.contains("onCommit()"),
                      "The VoiceOver adjustment does not call `onCommit()`, so the value it "
                      + "changed is never persisted or settled. Closure was:\n\(closure)")
    }

    /// The unknown-direction branch must NOT fall through to the callbacks. Nothing moved, so
    /// firing every live-apply and persist closure would push a phantom edit through the engine —
    /// which is exactly what `break` did once `onChange()` was added above it.
    ///
    /// Matched on WHITESPACE-STRIPPED text, because a literal `"@unknown default: return"` would
    /// redden this gate if the branch were merely reformatted onto two lines — which SwiftLint's
    /// own opt-in `switch_case_on_newline` would ask for. A guard that fails on formatting is a
    /// guard people delete.
    func testAnUnhandledDirectionNotifiesNothing() throws {
        let closure = try closureBody(after: ".accessibilityAdjustableAction {", in: Self.field)
        let squashed = closure.components(separatedBy: .whitespacesAndNewlines).joined()
        XCTAssertTrue(squashed.contains("@unknowndefault:return"),
                      "The `@unknown default` branch does not `return`, so it falls through to "
                      + "`onChange()`/`onCommit()`. An unhandled adjustment direction changed no "
                      + "value; announcing a change for it is a phantom edit. Closure was:\n"
                      + closure)
    }

    /// A swipe at a range EDGE must notify nobody either — `apply` clamps, so the value is
    /// unchanged, and two of `EchoelStudioView`'s ten `onChange` closures are destructive with an
    /// unchanged value: `visualPresetID = ""` (4 rows) clears the user's chosen visual look and is
    /// `@AppStorage`, so the loss survives the launch; `applyArticulation()` re-derives A/D/S/R
    /// from the macro. Swiping past the top must not undo work.
    ///
    /// ⛔ I CHANGED THAT "TWO" TO "ONE" AND HAD TO CHANGE IT BACK ONE COMMIT LATER — the retraction
    /// is the mistake worth recording, not the original. My argument was that `applyArticulation()`
    /// is a pure function of `articulation` and therefore comes back with the restored number.
    /// Pure it is; irrelevant, because its four outputs are INDEPENDENTLY EDITABLE rows
    /// (`param("Attack", $currentPatch.attack, …)` and its three neighbours), so re-deriving them
    /// restores the macro's envelope over a hand-shaped one. One #378 reviewer asked me to spread
    /// the "one" to three more places; the other refuted it outright. Reading the source settled
    /// it in a minute. **A retraction needs the same evidence a claim does** — mine had none, and
    /// it would have propagated a false count into four files.
    func testAClampedEdgeSwipeNotifiesNothing() throws {
        let closure = try closureBody(after: ".accessibilityAdjustableAction {", in: Self.field)
        let squashed = closure.components(separatedBy: .whitespacesAndNewlines).joined()
        // ⛔ THIS NEEDLE WAS `guardvalue!=beforeelse{return}` UNTIL #375, AND ITS BREAKING IS THE
        // POINT OF THIS NOTE. #375 moved the "did it move" question into `apply`'s return value
        // for ALL THREE paths, so this closure now reads `guard moved else { return }` — the same
        // rule, asked one layer down. The author of #375 did not grep for existing guards on the
        // file being changed and would have reddened the only blocking gate; the compile check
        // builds `Sources/` only and would have stayed green. When you change a source line,
        // `git grep` the literal in `Tests/CISmoke` BEFORE committing.
        XCTAssertTrue(squashed.contains("guardmovedelse{return}"),
                      "The adjustment notifies unconditionally, so a swipe against the range "
                      + "limit fires the live-apply closures with a value that did not change. "
                      + "Closure was:\n\(closure)")
    }

    // MARK: - The step has to be able to move the value

    /// ⛔ THE OTHER HALF. `apply(_:)` snaps to the `10^decimals` grid, so a step below half a
    /// grid unit rounds back to the starting value: the swipe is wired, announced, and inert.
    /// These are the real shipped ranges that were frozen.
    func testEverySwipeCanActuallyMoveAWholeNumberField() {
        // label, range width, decimals
        let frozenBefore: [(String, Double, Int)] = [
            ("Beats per bar 1…12", 11, 0),
            ("Field Voices 1…8", 7, 0),
            ("FX Bits 1…16", 15, 0),
            ("Harmonizer interval −12…12 (since replaced by a named-interval picker)", 24, 0),
        ]
        for (name, span, decimals) in frozenBefore {
            let step = ScrubPrecision.adjustmentStep(span: span, decimals: decimals)
            let grid = pow(10.0, -Double(decimals))
            XCTAssertGreaterThanOrEqual(step, grid / 2 + .ulpOfOne,
                                        "\(name): a step of \(step) snaps back to the same value "
                                        + "on a \(grid) grid — the field cannot be adjusted by "
                                        + "VoiceOver at all.")
            // The concrete consequence: one swipe from the low end must land on a DIFFERENT
            // snapped value. This is the assertion that fails on the old `span / 50`.
            let snapped = ((1.0 + step) / grid).rounded() * grid
            XCTAssertNotEqual(snapped, 1.0, "\(name): one swipe from 1 lands back on 1")
        }
    }

    /// …and the fields that could already move must move by exactly as much as before: 50 swipes
    /// across the range stays the design wherever the grid is not the binding constraint.
    func testCoarseFieldsKeepTheOldFiftiethStep() {
        XCTAssertEqual(ScrubPrecision.adjustmentStep(span: 17_980, decimals: 0), 17_980 / 50,
                       "a 20…18000 Hz cutoff must still take 50 swipes, not 17 980")
        XCTAssertEqual(ScrubPrecision.adjustmentStep(span: 1, decimals: 4), 1.0 / 50,
                       "a 0…1 mix at 4 decimals was never grid-limited")
        XCTAssertEqual(ScrubPrecision.adjustmentStep(span: 63, decimals: 0), 63.0 / 50,
                       "a 1…64 range is wider than 25, so the fiftieth already cleared the grid")
    }

    /// A degenerate range must fall back to one grid unit, not to zero — the whole point is that
    /// a control which cannot move is the defect. `pow` is not required to be bit-exact, so the
    /// fractional grid is compared with a tolerance rather than for equality.
    func testADegenerateRangeStillYieldsAMovableStep() {
        XCTAssertEqual(ScrubPrecision.adjustmentStep(span: 0, decimals: 0), 1,
                       "an empty range must still yield a movable step")
        XCTAssertEqual(ScrubPrecision.adjustmentStep(span: .nan, decimals: 2), 0.01,
                       accuracy: 1e-12,
                       "a NaN span must fall back to the grid, not propagate")
        // ⚠️ An infinite span returns the GRID, not infinity. My first draft of this test asserted
        // `.infinity` on the reasoning that `span/50` is the larger value — but the guard rejects
        // any non-finite fiftieth before the comparison, deliberately: an unbounded step is not a
        // usable adjustment, and "not finite" is exactly the class the guard exists to catch.
        XCTAssertEqual(ScrubPrecision.adjustmentStep(span: .infinity, decimals: 0), 1,
                       "a non-finite span is rejected by the guard like any other, and falls back "
                       + "to one grid unit rather than to an unbounded jump")
    }

    /// Guards the PREMISE the header states: that `apply(_:)` notifies nobody, which is why each
    /// call site has to. If `apply` ever starts calling the callbacks itself, the three paths
    /// would double-notify and this whole file is asking the wrong question — so it fails loudly
    /// rather than keeping a stale rationale alive.
    ///
    /// ⛔ THE MARKER DELIBERATELY STOPS BEFORE THE BRACE. It used to include `{`, and #375 —
    /// which gave `apply` a `-> Bool` return so all three paths could ask "did it move" — moved
    /// the brace and turned this into `XCTFail("Marker not found")`. A guard pinned to a
    /// signature's punctuation fails on the change it was meant to survive. Matching the
    /// parameter list alone is still unique (`git grep -c "private func apply(_ raw: Double)"
    /// -- Sources` → 1) and survives a return type, an attribute or a reformat.
    func testApplyItselfStillNotifiesNobody() throws {
        let body = try closureBody(after: "private func apply(_ raw: Double)", in: Self.field)
        XCTAssertFalse(body.contains("onChange()") || body.contains("onCommit()"),
                       "`apply(_:)` now notifies on its own. That is defensible, but the three "
                       + "input paths all notify explicitly, so they would fire twice. Reconcile "
                       + "them and rewrite this file's premise. Body was:\n\(body)")
    }

    // MARK: - Reading the source

    /// The text from the line containing `marker` to its matching closing brace, with whole-line
    /// comments dropped. Brace-counting, and deliberately so: the alternative is no guard at all
    /// for a SwiftUI modifier closure.
    ///
    /// Comment lines are skipped BEFORE the brace arithmetic, not only before the append, so a
    /// comment holding an unbalanced brace cannot desync `depth` and silently return the wrong
    /// span. (An earlier draft justified the stripping as protection against the doc comments
    /// quoting `onChange()`/`onCommit()` by name — they discuss both callbacks but never write
    /// the parentheses, so that reason was false. The stripping is right; the argument was not.)
    private func closureBody(after marker: String, in relativePath: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(relativePath)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
        let matches = lines.indices.filter { lines[$0].contains(marker) }
        guard let start = matches.first else {
            XCTFail("Marker not found: \(marker) in \(relativePath) — it was renamed or moved. "
                    + "Re-point this test rather than deleting it.")
            throw CocoaError(.fileNoSuchFile)
        }
        XCTAssertEqual(matches.count, 1,
                       "Marker `\(marker)` appears \(matches.count) times; this scan reads only "
                       + "the first, so the guard may be pointing at the wrong one.")
        var depth = 0
        var collected: [String] = []
        for line in lines[start...] {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            collected.append(line)
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth == 0 && collected.count > 1 { break }
        }
        return collected.joined(separator: "\n")
    }

    /// `#filePath` is inside `Tests/CISmoke/`, so the repo root is three directories up. A
    /// source-reading test that cannot find the source must SKIP, not pass.
    private func repoRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
        guard FileManager.default.fileExists(atPath:
                root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("source tree not present — this test inspects source text, so it "
                          + "SKIPS rather than reporting a green it did not earn")
        }
        return root
    }
}
