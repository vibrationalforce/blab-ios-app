// TheDemoSourceAgreesWithItsOwnKnobTests.swift
// Echoel — #461. The Demo bio source published an RMSSD its own normalized knob contradicts.
//
// ⚠️ WHAT THIS FILE CAN AND CANNOT DO — FIRST, so nothing here reads stronger than it is.
// `BioSimulator.nextFrame()` is `private` and the class is `@MainActor`, so there is NO way to
// drive the shipped generator from here and read the frame it emits. Every claim below is
// therefore either (a) arithmetic on `HRVNormalization`, the real shipped converter, or (b) a
// SOURCE-TEXT SCAN pinning that `BioSimulator.swift` actually writes that arithmetic. Neither
// half is a run of the product. They are load-bearing only TOGETHER — the same shape as #431
// and #440: the arithmetic says what the right answer is, the scan says the source computes it.
//
// ⛔ THE FIRST VERSION OF THIS HEADER MIS-FILED ITS OWN TESTS — the exact #433 defect, committed
// in the slice that cites #433. It called `testTheKnobRoundTripsThroughTheSharedCeiling` a
// REGRESSION "red at every sampled point on `* 120`". It is GREEN on the old tree, and could not
// have been anything else: it evaluates `demoRMSSDms` below, which is the NEW formula written out
// here in the test file. Nothing in this file ever reads BioSimulator's multiplier AS A NUMBER —
// it cannot, the generator is unreachable. The 0.167 is a measurement of the old source's
// behaviour, not an assertion this file makes.
// **There is exactly ONE regression here: the source scan.** The claim also stood in the commit
// body and in CLAUDE.md; both are corrected. The lesson is the one #433 already paid for and it
// did not stick: mis-labelling your own tests is harder to see than a guard that cannot fail,
// because everything is green either way.
//
// ⛔ WHICH CLAIMS CAN FAIL, re-counted against the old tree instead of against how they read:
// (Listed in DECLARATION order, so the list and the file cannot drift apart. The first version
// listed them in a different order than it declared them — harmless on its own, except that
// CLAUDE.md pointed at "the third claim" and the reorder silently moved which test that was.
// Nothing here is referred to by ordinal any more, in this file or in CLAUDE.md.)
//   · `testTheDemoChainsToTheCeilingInsteadOfCopyingIt`  — THE REGRESSION. The old source held
//     the literal `* 120` and never named `HRVNormalization`.
//   · `testTheKnobRoundTripsThroughTheSharedCeiling`     — PREMISE. Green both sides. It states
//     what the right answer IS and binds it to the shipped converter; the scan states that the
//     source computes it. Only together do they mean anything.
//   · `testTheCeilingIsTheOneHouseCeiling`               — PREMISE. Green both sides. Without it
//     this file could drift from the app's converter and keep passing on its own arithmetic.
//   · `testTheOldDivisorDisagreedWithTheKnob`            — MUSEUM. It exists so the SIZE of the
//     fixed defect stays a number in the repo and not a sentence in a commit message. ⚠️ It is
//     NOT green "by construction", as the first version claimed: it calls the real
//     `normalize(60)` and expects 0.60, so moving the house ceiling — which the premise above
//     explicitly declares allowed — turns it red. That is a real coupling, and its failure
//     message says so instead of misdirecting to "the museum is wrong, not the app".
//   · `testSDNNAndPNN50AreDeliberatelyNotRoundTripped`   — COUNTERWEIGHT for #461, and since
//     #464 also the REGRESSION for a SECOND baseline (see the note below). It exists so the
//     symmetrical-looking "tidy-up" (give SDNN the ceiling neat) turns red instead of silently
//     making demo SDNN identical to demo RMSSD.
//   · `testThePublishedMillisecondsStayInsideTheReadoutBand` — COUNTERWEIGHT. Green across both
//     slices (every band this file has shipped was inside). It pins the thing a *different*
//     anchor choice would have broken: `BioStripView` blanks the HRV readout outside 3…300 ms,
//     so a fix that anchored to a small ceiling — or, after #464, a resting ratio big enough to
//     push the SDNN walk past 300 — would silently empty the Demo readout rather than correct it.
//
// ⚠️ TWO BASELINES, because this file now guards TWO slices and "is it red?" has no answer
// without saying red against WHAT. ⛔ AND THE FIRST VERSION OF THIS PARAGRAPH GOT ITS OWN
// GRADING WRONG THREE WAYS — both #464 reviewers found it independently, and every count is
// verified below. It said "Against the pre-#461 tree exactly one claim fails: the RMSSD scan",
// and it said the two new arithmetic claims "could not even have COMPILED" — two sentences that
// cannot both be operative, because the second destroys the first.
//   · `git show c93ae1b^:…/BioSimulator.swift` carries **both** `* 120` and `* 90`, so today's
//     SDNN scan is red there too: **two** red against pre-#461, not one.
//   · `demoSDNNms` is a FILE-LEVEL helper reading `BioSimulator.restingSDNNOverRMSSD`, so as
//     written **this file compiles against NEITHER older tree** and no claim in it can be graded
//     against either. The runnable statement needs the constant references deleted first.
//   · There are **FOUR** new symbol-dependent sites, not two: the ratio check, the two loop
//     claims (both via `demoSDNNms`), and the `("SDNN", demoSDNNms(h))` tuple in the band test.
// The honest form: **this is a historical narrative, not a reproducible check.** Each baseline
// is silently paired with its CONTEMPORANEOUS version of this guard — pre-#461 with the version
// that pinned `* 120` and `* 90`, pre-#464 with the version that pinned `* 90`. Under that
// pairing, and only under it, each baseline has exactly one red claim. The forward-guard
// classification stands (calling the new arithmetic "regressions" would be the #433
// self-mis-filing); the counts and the executability did not.
//
// ⭐ THE DEFECT. `HRVNormalization` exists because #97 found the live sources each carrying their
// OWN divisor for the SAME `hrvNormalized` field (camera ÷200, strap ÷100, HealthKit ÷100). It
// collapsed them onto one 100 ms ceiling. The DEMO source was not in that audit and kept a fourth
// divisor — 120 for RMSSD — so the frame it published was internally unreconcilable: at
// `hrvNormalized` 0.5 it shipped 60 ms, while the app's own rule says 60 ms is 0.60.
//
// ⚠️ THE INVARIANT IS SOURCE-DEPENDENT AND THAT IS WHY THE ANCHOR IS RMSSD. On camera and Polar
// the knob is `normalize(rmssd)`; on HealthKit it is `normalize(sdnn)`, because HealthKit has no
// beat-to-beat RR. (A fourth producer, `FaceExpressionBioPublisher`, satisfies it vacuously — it
// publishes `hrvNormalized: 0` and no ms metric at all.) The demo publishes RMSSD *and* pNN50 —
// quantities only an RR source has — so it belongs to the RR convention. Anchoring it on SDNN
// would have been a third rule.
//
// ⚠️ NOT PROVEN HERE: that any of this is visible or audible. The two CONSUMERS of `hrvRMSSDms`
// are the OSC egress (`/echoelmusic/bio/heart/rmssd`) and `BioStripView`'s readout (a third read
// exists — the camera's dropout hold-repeat carrying `held.hrvRMSSDms` forward — but that is a
// carry, not a consumer; "the two readers app-wide" was the loose first wording);
// whether a lighting desk or a founder ever looks at the demo's number is a device question.
// The arithmetic is wrong either way, which is why it is fixed rather than deferred.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheDemoSourceAgreesWithItsOwnKnobTests: XCTestCase {

    /// The walk band `BioSimulator.nextFrame()` clamps `hrvNormalized` into.
    private static let walkBand: ClosedRange<Float> = 0.2...0.9

    /// The shipped expression, reproduced. Kept as ONE symbol so the scan below and the
    /// arithmetic above cannot describe different things.
    private func demoRMSSDms(_ hrvNormalized: Float) -> Float {
        hrvNormalized * Float(HRVNormalization.ceilingMs)
    }

    /// The REMOVED expression, reproduced for the museum test only. Nothing else may use it.
    private func retiredDemoRMSSDms(_ hrvNormalized: Float) -> Float {
        hrvNormalized * 120
    }

    /// The shipped SDNN expression, reproduced. Unlike the RMSSD twin above this READS the
    /// source's own constant rather than restating a number, so moving the ratio moves this file
    /// with it instead of leaving a stale hand copy behind (the failure mode the pre-#464 version
    /// of the counterweight admitted to in its own comment).
    private func demoSDNNms(_ hrvNormalized: Float) -> Float {
        hrvNormalized * Float(HRVNormalization.ceilingMs * BioSimulator.restingSDNNOverRMSSD)
    }

    // MARK: - The regression

    /// THE REGRESSION — red on the old tree. The demo must READ the house ceiling on the RMSSD
    /// line itself. Two failure shapes this must catch, and the first version caught neither
    /// properly: a restated literal `100` (the #97 copy-drift defect with a correct value today),
    /// and — because the first version scanned the WHOLE FILE for the bare token — a tree where
    /// `ceilingMs` appears on the *SDNN* line while RMSSD carries a literal. That shape passed
    /// both of the original assertions while re-opening the exact defect this file exists for.
    /// #408's lesson verbatim: anchor on a token that appears ONLY at the intended place.
    func testTheDemoChainsToTheCeilingInsteadOfCopyingIt() throws {
        let source = try demoSource()
        XCTAssertTrue(
            source.contains("hrvRMSSDms: hrvNormalized * Float(HRVNormalization.ceilingMs)"),
            """
            BioSimulator's RMSSD line must derive from HRVNormalization.ceilingMs. A restated \
            literal is the #97 copy-drift defect with a correct value today — and the whole \
            expression is pinned, not the bare token, because `ceilingMs` appearing SOMEWHERE in \
            this file proves nothing about the line that publishes RMSSD.
            """)
        XCTAssertFalse(
            source.contains("hrvRMSSDms: hrvNormalized * 120"),
            """
            BioSimulator still holds the fourth divisor (* 120) that #97 removed from the live \
            sources.
            """)
    }

    // MARK: - Premises

    /// PREMISE — green both sides. States what the right answer IS: every point of the walk band
    /// must survive the app's own ms→knob converter unchanged. It is NOT evidence that the source
    /// computes this — that is the scan's job, and this test cannot do it (the generator is
    /// private and `@MainActor`).
    func testTheKnobRoundTripsThroughTheSharedCeiling() {
        let steps = 701
        var worstAbsolute: Double = 0
        var worstAt: Float = 0
        for i in 0..<steps {
            let t = Float(i) / Float(steps - 1)
            let h = Self.walkBand.lowerBound
                + (Self.walkBand.upperBound - Self.walkBand.lowerBound) * t
            let backToKnob = Float(HRVNormalization.normalize(Double(demoRMSSDms(h))))
            let delta = abs(Double(backToKnob - h))
            if delta > worstAbsolute { worstAbsolute = delta; worstAt = h }
        }
        // Float→Double→Float round-tripping, not an approximation of the rule: the rule is
        // exact division by the ceiling, so only representation error may remain. Measured
        // worst residual on this grid: 5.960464477539063e-08.
        XCTAssertLessThan(
            worstAbsolute, 1e-6,
            """
            The Demo source's RMSSD formula does not survive the app's own converter. Worst \
            disagreement \(worstAbsolute) at hrvNormalized \(worstAt). On every real source \
            hrvNormalized == HRVNormalization.normalize(<that source's ms metric>) to \
            representation; the demo must not be the one source where recomputing the knob from \
            the wire value gives a different number.
            """)
    }

    /// PREMISE — green both sides. Binds this file's arithmetic to the app's converter, so the
    /// guard cannot drift into testing its own private idea of normalization.
    func testTheCeilingIsTheOneHouseCeiling() {
        XCTAssertEqual(HRVNormalization.ceilingMs, 100.0, accuracy: 1e-12,
                       """
                       The shared HRV ceiling moved. That is allowed — but every source, \
                       including the Demo generator, must move with it.
                       """)
        // `normalize` must be plain division below the ceiling; the round-trip proof rests on it.
        XCTAssertEqual(HRVNormalization.normalize(50), 0.5, accuracy: 1e-12)
        XCTAssertEqual(HRVNormalization.normalize(250), 1.0, accuracy: 1e-12, "clamps at the top")
        XCTAssertEqual(HRVNormalization.normalize(0), 0.0, accuracy: 1e-12, "0 = no usable HRV")
    }

    // MARK: - Museum

    /// MUSEUM — documentation, not a regression, and labelled so rather than counted as one.
    /// It exists because the SIZE of a fixed defect otherwise survives only in a commit message.
    ///
    /// ⚠️ It is NOT "green by construction", which is what the first version claimed. It computes
    /// the REMOVED formula itself (so `BioSimulator` cannot break it), but it then feeds the
    /// result to the REAL `HRVNormalization.normalize` and expects 0.60 — so it is coupled to
    /// `ceilingMs == 100`, and `testTheCeilingIsTheOneHouseCeiling` twenty lines up explicitly
    /// says moving that ceiling is allowed. If both go red together, the ceiling moved and BOTH
    /// expectations need updating; only this one red means the museum is wrong.
    ///
    /// Two numbers, both carrying their setup (#448), because the first write-up quoted one and
    /// called it the other: at `hrvNormalized` 0.5 the old formula published 60 ms, which the
    /// house rule reads back as 0.60 — a flat **+20 % relative**, 0.1 absolute, exact. The worst
    /// ABSOLUTE error is the analytic supremum **1/6 ≈ 0.16667** at h = 5/6; the 701-point grid
    /// above never lands on 5/6 and reaches **0.16660** at h ≈ 0.833. The +20 % is flat only up to
    /// 5/6 — beyond it `normalize` clamps, so the top of the band (0.9) reads +11 %, which looks
    /// like the error shrinking and is really the converter saturating.
    func testTheOldDivisorDisagreedWithTheKnob() {
        let h: Float = 0.5
        let oldMs = retiredDemoRMSSDms(h)
        XCTAssertEqual(oldMs, 60, accuracy: 1e-6)
        let backToKnob = Float(HRVNormalization.normalize(Double(oldMs)))
        XCTAssertEqual(backToKnob, 0.6, accuracy: 1e-6,
                       "the house rule reads 60 ms as 0.60, not as the 0.50 the demo shipped")
        XCTAssertEqual(Double(abs(backToKnob - h)), 0.1, accuracy: 1e-6,
                       """
                       0.1 absolute at the middle of the walk band — the number this slice \
                       removed. ⚠️ If this is red TOGETHER WITH testTheCeilingIsTheOneHouseCeiling, \
                       the house ceiling moved (which that test says is allowed) and BOTH \
                       expectations need updating. If it is red ALONE, the museum is wrong.
                       """)
    }

    // MARK: - Counterweights

    /// REGRESSION (against the pre-#464 tree) + COUNTERWEIGHT, in one method because the two
    /// claims are the same decision seen from both sides.
    ///
    /// The tidy-up that looks like consistency is to give SDNN the ceiling NEAT. It is not
    /// consistency: on camera and Polar SDNN does not round-trip either (the knob is anchored on
    /// RMSSD there too), and doing it here would make the demo's SDNN bit-identical to its RMSSD
    /// — a pair no body produces, and one that makes the Demo source useless for testing a
    /// receiver that plots the two separately. pNN50 is a percentage and no source ties it to the
    /// knob at all; it is pinned here too, because the first version argued for it in prose and
    /// asserted nothing, so the symmetrical tidy-up on pNN50 would have gone through under a test
    /// whose name promised to stop it.
    ///
    /// ⭐ WHAT #464 CHANGED HERE, stated so the update is a decision and not a silent re-pin: the
    /// scan used to pin `hrvSDNNms: hrvNormalized * 90`, and 90 sits BELOW the 100 ms ceiling, so
    /// the guard was faithfully defending an INVERTED pair (demo SDNN under demo RMSSD at every
    /// point, against every resting reference). The non-round-trip property was never the problem
    /// and is unchanged; only the direction was wrong. The pin moved in the same commit as the
    /// source, with the reason — it was not deleted.
    ///
    /// ⚠️ HONEST GRADING OF THE **FIVE** CLAIMS BELOW — ⛔ the first version said FOUR and left out
    /// the `XCTAssertNotEqual` at the end of the loop, i.e. the one this method is NAMED for. An
    /// enumeration is what a later session greps, so: (1) SDNN scan, (2) pNN50 scan, (3) ratio
    /// `> 1`, (4) direction per band point, (5) non-round-trip per band point.
    /// Claim 1 is a real regression against the pre-#464 tree. Claim 2 is green on both. Claims
    /// 3–5 COULD NOT HAVE RUN on the old tree at all — `restingSDNNOverRMSSD` did not exist, so
    /// the file would not have compiled; they are forward guards, not proof of a fixed defect,
    /// and calling them regressions would be the #433 self-mis-filing this file already paid for.
    ///
    /// ⚠️ Claims 3 and 4 are near-duplicates and the prose used to imply the wrong ordering:
    /// because `demoSDNNms` READS the module constant, they agree for every ratio distinguishable
    /// in `Float`. They part only within ~1e-8 of 1.0, and there claim 3 PASSES while claim 4
    /// FAILS — so the DIRECTION check is the stronger one, not the ratio check. Both stay: claim 3
    /// names the intent in the failure message, claim 4 is the one that actually holds the line.
    func testSDNNAndPNN50AreDeliberatelyNotRoundTripped() throws {
        let source = try demoSource()
        XCTAssertTrue(
            source.contains(
                "hrvSDNNms: hrvNormalized * Float(HRVNormalization.ceilingMs * Self.restingSDNNOverRMSSD)"),
            """
            The demo's SDNN must be the house ceiling TIMES the named resting ratio — not a bare \
            literal (which is how it came to sit below RMSSD in the first place) and not the \
            ceiling neat (which would make demo SDNN == demo RMSSD). If this line changed on \
            purpose, update this expectation in the SAME commit and say why; do not delete the \
            check. ⚠️ The needle pins the `Self.` spelling too (#408 wants a token unique to the \
            intended site) — so rewriting the source as `BioSimulator.restingSDNNOverRMSSD` turns \
            the blocking bundle red for a purely cosmetic edit. That red is spelling, not \
            regression.
            """)
        XCTAssertTrue(
            source.contains("hrvPNN50: hrvNormalized * 40"),
            """
            The demo's pNN50 is a percentage and is deliberately NOT anchored to the knob either. \
            Same rule as the SDNN line above: change it on purpose, in the same commit, with a \
            reason.
            """)

        // The ratio is the ONE property of #464 a guard can defend without inventing physiology:
        // above 1 the pair points the way a resting body does, at exactly 1 the two metrics
        // collapse into the same number. This reads the SOURCE's constant, so it is not the
        // tautology the pre-#464 version of this block honestly admitted to being (it compared a
        // literal 90 it had written itself).
        XCTAssertGreaterThan(
            BioSimulator.restingSDNNOverRMSSD, 1.0,
            """
            Demo SDNN must stay ABOVE demo RMSSD. At a ratio of exactly 1 the two are \
            bit-identical; below 1 the demo publishes the inverted pair #464 removed.
            """)

        for h in [Self.walkBand.lowerBound, 0.5, Self.walkBand.upperBound] {
            XCTAssertGreaterThan(
                demoSDNNms(h), demoRMSSDms(h),
                "at hrvNormalized \(h) the demo must publish SDNN above RMSSD, not below it")
            // And the non-round-trip survives the fix: 1.25·h never equals h on this band, and
            // above the clamp `normalize` saturates to 1.0, which is not h either.
            XCTAssertNotEqual(
                Float(HRVNormalization.normalize(Double(demoSDNNms(h)))), h,
                """
                Demo SDNN now round-trips through the knob — that is the collision this \
                counterweight exists to prevent, not a consistency win.
                """)
        }
    }

    /// COUNTERWEIGHT — green across #461 AND #464. Every band this file has shipped sits inside
    /// 3…300 ms: RMSSD 24…108 before #461 and 20…90 after; SDNN 18…81 before #464 and 25…112.5
    /// after. So this is not what either fix repaired — it pins what a DIFFERENT anchor choice
    /// would have broken.
    ///
    /// ⛔ THE TWO HALVES ARE NOT THE SAME KIND OF CLAIM, and the first version said they were.
    /// It wrote that an out-of-band SDNN "would have emptied the Demo readout", which is false:
    /// `git grep -n hrvSDNNms -- Sources/Echoelmusic/Studio` returns NOTHING. `BioStripView`'s
    /// "HRV" cell IS RMSSD — `hrvString` reads `hrvRMSSDms`, and `plausibleHRVms` is applied to
    /// that field only; `BioMetricInfo` says out loud that SDNN is a sub-measure of that cell and
    /// never a cell of its own. **No plausibility window constrains `hrvSDNNms` anywhere in
    /// `Sources/`.** So the SDNN half could fail numerically but not for its stated reason — the
    /// #367 defect, introduced by the very commit that pins it, in a file whose header polices
    /// exactly that. Both #464 reviewers caught it.
    ///   · RMSSD half: pins a REAL UI constraint (the strip blanks outside the band).
    ///   · SDNN half: pins a HAND-CHOSEN sanity bound on the OSC egress
    ///     (`/echoelmusic/bio/heart/sdnn`), whose only real gate is `hrvSDNNms > 0`. Kept because
    ///     a 300+ ms demo SDNN on a foreign console is implausible on its own terms — but it
    ///     mirrors no window, and at the cited upper bracket (≈2.0) the top would read 180 ms.
    ///
    /// ⚠️ The RMSSD band is a HAND COPY. `BioStripView.plausibleHRVms` is `private static`, so
    /// nothing binds these two together — if the strip narrows its window, this test stays green
    /// and the Demo readout goes blank without a red anywhere. Stated rather than papered over.
    func testThePublishedMillisecondsStayInsideTheReadoutBand() {
        let readable: ClosedRange<Float> = 3...300
        for h in [Self.walkBand.lowerBound, 0.5, Self.walkBand.upperBound] {
            for (name, ms) in [("RMSSD", demoRMSSDms(h)), ("SDNN", demoSDNNms(h))] {
                XCTAssertTrue(
                    readable.contains(ms),
                    """
                    Demo \(name) \(ms) ms at hrvNormalized \(h) falls outside 3…300 ms. For \
                    RMSSD that IS BioStripView's window, so the readout would show "—" for a \
                    source whose whole purpose is to give the readouts something to display. \
                    For SDNN nothing in Sources/ constrains the value — this is a hand-chosen \
                    sanity bound on the OSC egress, not a mirror of a UI window.
                    """)
            }
        }
    }

    // MARK: - Helpers

    private func demoSource() throws -> String {
        let url = try repoRoot()
            .appendingPathComponent("Sources/Echoelmusic/Bio/BioSimulator.swift")
        // Comments stripped through the ONE shared scanner (#453).
        // ⚠️ HONEST ABOUT WHAT THIS BUYS TODAY: nothing. Measured on both trees, raw text and
        // `codeOnly` give IDENTICAL results for all four needles, because the needles are
        // whole expressions (`hrvRMSSDms: hrvNormalized * 120`) and the source's ⛔ block only
        // quotes the fragment `hrvNormalized * 120`. The first version claimed the stripper was
        // load-bearing — true of the LOOSE needle it had before the #408 tightening, false now.
        // It stays because it is the house scanner and the next edit to that comment block is
        // one keystroke from re-introducing the collision; it is prophylaxis, not a fix.
        // (The same sentence also said "this file's own prose quotes both" — irrelevant in any
        // version: the scan reads `BioSimulator.swift`, never this file.)
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — this test inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
