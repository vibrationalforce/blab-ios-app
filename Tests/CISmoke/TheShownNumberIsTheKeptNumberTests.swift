//
//  TheShownNumberIsTheKeptNumberTests.swift
//  Echoelmusic — CISmoke (blocking bundle)
//
//  #432. The app's one parameter control rounded the number it SHOWED and the number it KEPT by
//  two different rules, and had done since both halves existed.
//
//    · KEPT: `ScrubPrecision.snapped` → `.rounded()`, which is IEEE round-half-AWAY-from-zero.
//    · SHOWN: `EchoelDecimalText.string` → `String(format: "%.Nf", …)`, which is C `printf` and
//      rounds half-to-EVEN on the exact binary value.
//
//  They agree on every value that is not an exact dyadic tie. At a tie they disagree exactly
//  half the time — whenever the even neighbour is the LOWER one. Measured over the constructed
//  ties below, **30 of every 60**, at all five decimal settings the app uses:
//
//      0 places   0.5 → read "0"      kept 1
//      1 place    0.25 → read "0.2"   kept 0.3
//      2 places   0.125 → read "0.12" kept 0.13     (0.375 and 0.875 agreed)
//      3 places   0.0625 → "0.062"    kept 0.063
//      4 places   0.03125 → "0.0312"  kept 0.0313
//
//  ⭐ AND THE REACH IS NOT AN EXOTIC CORNER. On the Cutoff row's own span, **8990 of the 17980
//  half-integers in 20…18000 diverge** — every other one. A tie is only reachable for a value
//  nothing has snapped yet, which is precisely the interesting set: a shipped patch literal, a
//  value written by bio modulation or the "Describe it" prompt, or a DERIVED binding like
//  `EchoelStudioView.visualEnergy`, whose getter recomputes from two other stored values and
//  therefore lands off-grid by construction (#427 measured 62 of 101 positions off-grid there).
//  The player reads one number; the first touch keeps a different one. That is the
//  #135/#416/#427/#431 condition on the last path where it survived.
//
//  THE FIX IS ONE RULE PER CONTROL, not a new rule: `ScrubPrecision.gridded` is `snapped`'s
//  rounding step lifted out of it, and both readouts (`EchoelValueField.numberString`,
//  `EchoelNumberPad.fmt`) now format the GRIDDED value. `snapped` is redefined in terms of it and
//  the keypad's private copy of the same arithmetic is gone, so there is one definition instead
//  of three (#416).
//
//  ⚠️ IT GRIDS BUT DOES NOT CLAMP, and that asymmetry is the point rather than an oversight.
//  Gridding moves a number by less than half a step, so a readout that grids still describes the
//  value it is drawn from. Clamping can move it by any amount at all — a readout that clamped
//  would claim a value is inside a range it is outside of, which is a worse lie than the one
//  being fixed. `snapped` keeps the clamp because a COMMIT must land in range.
//
//  ⚠️ WHAT THIS FILE CANNOT DO, stated because two of its four tests are near-tautologies and it
//  would be easy to read the green as more than it is:
//    · `numberString` and `fmt` are both `private` inside SwiftUI views. Nothing here can call
//      them. The coupling between "the display path grids" and "the commit path grids" is held
//      by the SOURCE SCAN below, not by the arithmetic tests — and a scan can go red for a
//      reformat and green for a rename.
//    · `testTheGridAndTheCommitAgreeInRange` is true by construction now that `snapped` is
//      defined as `gridded(clamped(…))`. It is kept as the statement of the invariant, not as
//      the regression. The REGRESSION is `testTheOldFormatterDisagreedWithTheCommit`, which
//      measures the old route and goes red if `gridded` is ever changed to round half-to-even
//      "for consistency with printf" — the plausible wrong repair.
//    · Nothing here proves a device renders anything.
//
//  ⛔ ONE MEASURED THING WAS ALMOST ASSERTED WRONGLY, AND IT IS RECORDED BECAUSE THE WRONG MODEL
//  LOOKED LIKE A DEFECT. A Python model of this change reported 64 divergences on ordinary non-tie
//  values, all of the form "-0" → "0" for small negative inputs at `decimals: 0`. Had that been
//  real it would have hit six shipped rows (Transpose ±12/±24, Detune, Trim −48…0, pan −1…1). It
//  is an artefact of the MODEL — a naïve `floor(x + 0.5)` — not of the code: Swift's `.rounded()`
//  is `toNearestOrAwayFromZero`, i.e. IEEE-754 `roundToIntegralTiesAway`, which PRESERVES the sign
//  of a zero result, so `(-0.258).rounded()` is `-0.0` and `printf` still prints "-0". The first
//  version of this file responded by restricting the no-op sweep to non-negative values and saying
//  so honestly. That was the weaker sentence dressed as the stronger one: the claim "safe to apply
//  to every readout in the app" cannot rest on a sweep that skips half the shipped domain. The
//  sweep now covers the negative ranges too, on the IEEE rule and not on a model.
//
//  ⚠️ THE TITLE'S PROMISE IS CONDITIONAL ON THE RANGE, and that is by design (#431). Typing `999`
//  into a 0…1 row shows `999` in the keypad's 30-pt readout and commits `1.00` — a far larger
//  visible gap than any tie, deliberately preserved, because a range PREFIX is the ordinary middle
//  of a valid entry (`8` is outside 20…18000 on the way to `800`). "The shown number is the kept
//  number" is a statement about ROUNDING. The clamp is a separate, louder, intentional divergence.
//

import Foundation
import XCTest
@testable import Echoelmusic

final class TheShownNumberIsTheKeptNumberTests: XCTestCase {

    /// The five decimal settings the app actually ships.
    ///
    /// ⛔ The first version of this line said "five" and then listed FOUR — 0 · 2 · 3 on the Sound
    /// panel, 4 on concert pitch and locked tempo — and claimed "2 across FX". Both halves wrong:
    /// `decimals: 1` is shipped, and it is shipped IN FX, on six rows of the dynamics section
    /// (`EchoelFXView.swift:573` Threshold · `:574` Ratio · `:591` Attack · `:593` Knee · `:594`
    /// Make-up · `:598` Ceiling, all through `field(…)`). The array was right and the prose was
    /// wrong, which is the harder direction to catch: nothing goes red for a miscounted sentence.
    /// Computed, not a stored `static let`. Under Swift 6 language mode a stored static is a
    /// concurrency-safety question every time (SE-0412), and the previous slice in this chain
    /// turned the blocking gate red on exactly that. A computed static has no storage, so the
    /// question does not arise — and there is nothing here worth storing.
    private static var decimalSettings: [Int] { [0, 1, 2, 3, 4] }

    /// Exact dyadic ties for `decimals` places: odd multiples of `2^-(decimals+1)`.
    ///
    /// Constructed rather than listed, because a hand-written list of ties is a list of the ones
    /// somebody thought of. `(2k+1) · 2^-(d+1)` is exact in `Double` (a small integer times a
    /// power of two), and `v · 10^d = (2k+1) · 5^d / 2` always ends in .5 because `(2k+1) · 5^d`
    /// is odd. Each value is checked to BE a tie before it is used — a "tie test" whose inputs
    /// are not ties is the #367 class.
    private static func ties(decimals d: Int, count: Int = 60) -> [Double] {
        let step = pow(2.0, -Double(d + 1))
        return (0..<count).map { Double(2 * $0 + 1) * step }
    }

    private static func isTie(_ v: Double, decimals d: Int) -> Bool {
        let x = v * pow(10.0, Double(d))
        return abs(x - x.rounded(.down) - 0.5) < 1e-12
    }

    /// The string a readout draws, in a fixed locale so the assertion is about ROUNDING and not
    /// about whether the runner speaks German (#232 G made the separator locale-aware).
    ///
    /// Computed, not a stored `static let`, for the same reason as `decimalSettings` above: under
    /// Swift 6 language mode a stored static is a concurrency-safety question every time (SE-0412),
    /// and the previous slice in this chain turned the blocking gate red on exactly that. `Locale`
    /// is almost certainly `Sendable`, but "almost certainly" is what the red gate cost — and a
    /// computed static has no storage, so the question does not arise.
    private static var posix: Locale { Locale(identifier: "en_US_POSIX") }

    private static func shown(_ v: Double, _ d: Int) -> String {
        EchoelDecimalText.string(ScrubPrecision.gridded(v, decimals: d), decimals: d, locale: posix)
    }

    private static func rawPrintf(_ v: Double, _ d: Int) -> String {
        EchoelDecimalText.string(v, decimals: d, locale: posix)
    }

    // MARK: - The regression

    /// THE ONE TEST HERE THAT MEASURES THE DEFECT. It goes red if `ScrubPrecision.gridded` is
    /// ever changed to round half-to-even — the plausible wrong repair, made "for consistency
    /// with printf" — because then the two routes would agree at every tie and the count of
    /// disagreements would fall to zero, which is the same as saying the defect was imaginary.
    ///
    /// It asserts a MEASURED number rather than "> 0": half the ties at every setting. A
    /// threshold of "at least one" would survive a change that silently fixed 59 of 60.
    func testTheOldFormatterDisagreedWithTheCommit() {
        // THE CANONICAL CASE FIRST, deliberately, so that a PLATFORM surprise names itself.
        // The whole premise is that Darwin's `printf` rounds ties to even. If a runner's libc ever
        // rounded them away from zero instead, the loop below would report five confusing
        // "expected 30, got 0" failures and nothing would say why. These two lines say why.
        XCTAssertEqual(Self.rawPrintf(0.125, 2), "0.12", """
            This runner's `printf` did not round 0.125 down to the even neighbour. #432's premise \
            is that `String(format: "%.Nf", …)` rounds half-to-even on the exact binary value; if \
            that is false here, the failures below are a PLATFORM difference and not a regression \
            in `ScrubPrecision.gridded`.
            """)
        XCTAssertEqual(Self.shown(0.125, 2), "0.13", """
            The app's grid did not round 0.125 away from zero. `ScrubPrecision.gridded` uses \
            `.rounded()`, which is `toNearestOrAwayFromZero`; if this fails, the grid's rule was \
            changed and every count below is measuring the new rule, not the defect.
            """)

        for d in Self.decimalSettings {
            let ties = Self.ties(decimals: d)
            for t in ties {
                XCTAssertTrue(Self.isTie(t, decimals: d), """
                    \(t) is not an exact tie at \(d) places, so this test would be measuring \
                    nothing. The construction in `ties(decimals:)` is wrong, not the app.
                    """)
            }
            let disagreed = ties.filter { Self.rawPrintf($0, d) != Self.shown($0, d) }
            XCTAssertEqual(disagreed.count, ties.count / 2, """
                At \(d) decimal place(s), \(disagreed.count) of \(ties.count) exact ties are \
                formatted differently by `printf` than by the app's grid, and the measured \
                answer is exactly half — every tie whose lower neighbour is even. Getting a \
                different count means the grid's rounding rule changed. If it fell to 0, \
                `ScrubPrecision.gridded` now rounds half-to-even and the #432 defect is back \
                (the readout would once again describe a different grid cell than the commit).
                """)
        }
    }

    // MARK: - The invariant

    /// What the row SHOWS is the string of what the row would KEEP.
    ///
    /// True by construction since `snapped` became `gridded(clamped(…))` — kept as the statement
    /// of the contract, not as a regression (the header says so). It still earns its place: it
    /// fails if someone re-inlines a second rounding into either half.
    ///
    /// ⚠️ WHAT ITS GREEN DOES NOT MEAN. `snapped` clamps and THEN grids, so a commit can land up
    /// to half a grid step OUTSIDE its own bound: `snapped(1.5, lowerBound: 0, upperBound: 1.5,
    /// decimals: 0)` is `2.0`. This test includes exactly that pair and passes, because both sides
    /// render "2" — the test is about the two ROUNDINGS agreeing, not about the commit landing in
    /// range. The overshoot is pre-existing (`EchoelValueField.swift`, untouched by #432) and
    /// unreachable today: every shipped `0...1.5` row is `decimals: 2`. Registered as its own item
    /// rather than fixed here, because grid-then-clamp changes what `apply` writes.
    func testTheGridAndTheCommitAgreeInRange() {
        let ranges: [(Double, Double)] = [(0, 1), (0, 20), (20, 18000), (0, 10), (0, 12), (0, 1.5)]
        for d in Self.decimalSettings {
            for (lo, hi) in ranges {
                for t in Self.ties(decimals: d) where t >= lo && t <= hi {
                    let kept = ScrubPrecision.snapped(t, lowerBound: lo, upperBound: hi, decimals: d)
                    XCTAssertEqual(Self.shown(t, d),
                                   EchoelDecimalText.string(kept, decimals: d, locale: Self.posix), """
                        \(d) places, range \(lo)…\(hi): the row would DRAW \(Self.shown(t, d)) for \
                        \(t) and KEEP \(kept). A control that shows one number and stores another \
                        is the defect this file exists for.
                        """)
                }
            }
        }
    }

    /// EVERYTHING THAT IS NOT A TIE RENDERS EXACTLY AS BEFORE.
    ///
    /// This is the claim that makes the change safe to apply to every parameter readout in the
    /// app at once, so it is swept rather than sampled: 4000 pseudo-random values per range per
    /// decimal setting, deterministic seed, ties skipped (they are the other test's subject).
    ///
    /// THE NEGATIVE RANGES ARE IN THE SWEEP DELIBERATELY, and the header records why they nearly
    /// were not: a first Python model reported 64 "divergences" of the form "-0" → "0" at
    /// `decimals: 0`, which would have been a real defect on the six shipped rows that go below
    /// zero (Transpose ±12/±24, Detune, Trim −48…0, pan −1…1). The model was wrong, not the code.
    /// `Double.rounded()` is `toNearestOrAwayFromZero`, i.e. IEEE-754 `roundToIntegralTiesAway`,
    /// which PRESERVES the sign of a zero result — `(-0.4).rounded()` is `-0.0`, `-0.0 / 100` is
    /// `-0.0`, and `printf` prints "-0.00" exactly as it did before. Sweeping is the honest way to
    /// hold that: a claim that "nothing but a tie moved" while half the shipped rows' domain went
    /// untested is the weaker sentence pretending to be the stronger one.
    func testNothingButATieMoved() {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15   // fixed seed: a sweep must be reproducible
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) * (1.0 / 9007199254740992.0)   // [0, 1)
        }
        // Five non-negative spans from the shipped rows, then four that cross or sit below zero
        // (Trim −48…0, Transpose ±12 and ±24, pan −1…1) — see the doc above.
        let ranges: [(Double, Double)] = [(0, 1), (0, 20), (20, 18000), (0, 10), (0, 1.5),
                                          (-48, 0), (-12, 12), (-24, 24), (-1, 1)]
        var checked = 0
        for d in Self.decimalSettings {
            for (lo, hi) in ranges {
                for _ in 0..<4000 {
                    let v = lo + (hi - lo) * next()
                    guard !Self.isTie(v, decimals: d) else { continue }
                    checked += 1
                    XCTAssertEqual(Self.shown(v, d), Self.rawPrintf(v, d), """
                        \(v) at \(d) places is not a tie, yet gridding changed how it reads: \
                        "\(Self.rawPrintf(v, d))" → "\(Self.shown(v, d))". #432 was supposed to \
                        move ONLY exact ties; a wider change means the grid's arithmetic drifted \
                        from what printf does to the same value.
                        """)
                }
            }
        }
        XCTAssertGreaterThan(checked, 160_000, """
            Only \(checked) values were compared, so the "nothing but a tie moved" claim rests \
            on far less evidence than it says it does.
            """)
    }

    /// THE READOUT MUST NOT CLAMP. `gridded` moves a value by less than half a step; `snapped`
    /// can move it by the whole overshoot. Formatting the CLAMPED value would have been the
    /// easier fix and a worse one: the row would print a number inside its range for a value
    /// that is outside it, hiding exactly what #430 had to widen a row to reveal.
    func testTheReadoutDoesNotClamp() {
        XCTAssertEqual(ScrubPrecision.gridded(6.0, decimals: 2), 6.0,
                       "gridding must not move an in-grid value at all.")
        XCTAssertEqual(Self.shown(6.0, 2), "6.00",
                       "A 6.0 s decay must read as 6.00 even where a row's range stops earlier.")
        XCTAssertEqual(ScrubPrecision.snapped(6.0, lowerBound: 0, upperBound: 5, decimals: 2), 5.0,
                       "The COMMIT still clamps — that half is not being changed here.")
        // Non-finite survives untouched, so `printf` still prints what it always did.
        XCTAssertTrue(ScrubPrecision.gridded(Double.nan, decimals: 2).isNaN)
        XCTAssertEqual(ScrubPrecision.gridded(Double.infinity, decimals: 2), Double.infinity)
    }

    // MARK: - The wiring (source scan)

    /// THE HALF THAT ACTUALLY COUPLES THE TWO PATHS.
    ///
    /// The arithmetic tests above cannot reach `numberString` or `fmt` — both are `private`
    /// inside SwiftUI views. Without this scan the whole file could stay green while the two
    /// readouts went back to formatting the raw value. It anchors on the declarations existing
    /// FIRST (#367: a scan that only forbids a shape is green on a file that lost both shapes),
    /// and strips comment lines throughout (#404: a doc that NAMES the old form must not fail the
    /// guard that forbids it).
    ///
    /// ⚠️ BOTH HALVES READ COMMENT-STRIPPED SOURCE, not just the negative one. The first version
    /// stripped comments only before the forbidden shape, which is the #404 lesson applied to one
    /// side: in a repo whose comments routinely quote their own code, a future doc line quoting
    /// `ScrubPrecision.gridded(Double(value), decimals: decimals)` verbatim would have kept this
    /// guard green over a readout that no longer grids. An anchor that a comment can satisfy is
    /// not an anchor.
    func testBothReadoutsGridBeforeTheyFormat() throws {
        let root = try repoRoot()

        let field = Self.codeOnly(try String(contentsOf: root.appendingPathComponent(
            "Sources/Echoelmusic/Studio/EchoelValueField.swift"), encoding: .utf8))
        XCTAssertTrue(field.contains("private var numberString: String {"), """
            `EchoelValueField.numberString` is gone or renamed. Retarget this scan — the rule it \
            holds (one rounding per control) is not specific to the name.
            """)
        XCTAssertTrue(field.contains("ScrubPrecision.gridded(Double(value), decimals: decimals)"), """
            The field's readout no longer grids before it formats, so it is back to `printf`'s \
            half-to-even while `apply` keeps rounding half-away. That is #432 exactly: the row \
            draws one grid cell and stores another.
            """)
        XCTAssertTrue(field.contains("static func gridded(_ raw: Double, decimals: Int) -> Double"), """
            `ScrubPrecision.gridded` is gone. It is the app's ONE definition of what rounding a \
            parameter to `decimals` places means; without it the rule has to be re-copied at \
            every site, which is how it came to differ in the first place (#416).
            """)

        let pad = Self.codeOnly(try String(contentsOf: root.appendingPathComponent(
            "Sources/Echoelmusic/Studio/EchoelNumberPad.swift"), encoding: .utf8))
        XCTAssertTrue(pad.contains("private func fmt(_ v: Double) -> String {"),
                      "`EchoelNumberPad.fmt` is gone or renamed — retarget this scan.")
        XCTAssertTrue(pad.contains("ScrubPrecision.gridded(v, decimals: decimals)"), """
            The keypad's readout no longer grids before it formats. Tapping OK without typing \
            commits `initial`, so the big number on the pad and the number it writes would part \
            company again at every exact tie.
            """)

        // NEGATIVE HALF — the same comment-stripped text, because both files describe the old
        // arithmetic in prose on purpose and a naive scan would fail on the explanation of its
        // own rule.
        XCTAssertFalse(pad.contains("(v * f).rounded() / f"), """
            `EchoelNumberPad` keeps its own copy of the grid arithmetic again. Two definitions of \
            one rule is the #416 condition, and it is how the display and the commit came to \
            round differently — delegate to `ScrubPrecision.gridded`.
            """)
    }

    // MARK: - Helpers

    /// Source with whole-line `//` comments removed, so every needle below anchors on CODE.
    /// Deliberately line-based and not a real lexer: a trailing comment after code stays, which is
    /// the safe direction (it can only make a positive anchor easier and a negative one stricter).
    private static func codeOnly(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("Repo root not found from \(#filePath) — source scan cannot run.")
    }
}
