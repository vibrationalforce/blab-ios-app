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
//   · `testTheDemoChainsToTheCeilingInsteadOfCopyingIt`  — THE REGRESSION. The old source held
//     the literal `* 120` and never named `HRVNormalization`.
//   · `testTheKnobRoundTripsThroughTheSharedCeiling`     — PREMISE. Green both sides. It states
//     what the right answer IS and binds it to the shipped converter; the scan states that the
//     source computes it. Only together do they mean anything.
//   · `testTheOldDivisorDisagreedWithTheKnob`            — MUSEUM. Green both sides by
//     construction (it computes the removed formula itself). It exists so the SIZE of the fixed
//     defect stays a number in the repo and not a sentence in a commit message.
//   · `testSDNNAndPNN50AreDeliberatelyNotRoundTripped`   — COUNTERWEIGHT. Green before AND after.
//     It exists so the symmetrical-looking "tidy-up" (give SDNN the same ceiling) turns red
//     instead of silently making demo SDNN identical to demo RMSSD.
//   · `testTheCeilingIsTheOneHouseCeiling`               — PREMISE. Green both sides. Without it
//     this file could drift from the app's converter and keep passing on its own arithmetic.
//   · `testThePublishedMillisecondsStayInsideTheReadoutBand` — COUNTERWEIGHT. Green both sides
//     (24…108 was inside too). It pins the thing a *different* anchor choice would have broken:
//     `BioStripView` blanks the HRV readout outside 3…300 ms, so a fix that anchored to a small
//     ceiling would have silently emptied the Demo readout rather than corrected it.
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
// ⚠️ NOT PROVEN HERE: that any of this is visible or audible. The two readers of `hrvRMSSDms`
// app-wide are the OSC egress (`/echoelmusic/bio/heart/rmssd`) and `BioStripView`'s readout;
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

    /// MUSEUM — green both sides by construction, because it computes the removed formula itself.
    /// It is documentation, not a regression, and is labelled so rather than counted as one.
    /// It exists because the SIZE of a fixed defect otherwise survives only in a commit message.
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
                       removed. If this assertion is ever red, the museum is wrong, not the app.
                       """)
    }

    // MARK: - Counterweights

    /// COUNTERWEIGHT — green before and after. The tidy-up that looks like consistency is to
    /// give SDNN the same ceiling. It is not consistency: on camera and Polar SDNN does not
    /// round-trip either (the knob is anchored on RMSSD there too), and doing it here would make
    /// the demo's SDNN bit-identical to its RMSSD — a pair no body produces, and one that makes
    /// the Demo source useless for testing a receiver that plots the two separately. pNN50 is a
    /// percentage and no source ties it to the knob at all; it is pinned here too, because the
    /// first version argued for it in prose and asserted nothing, so the symmetrical tidy-up on
    /// pNN50 would have gone through under a test whose name promised to stop it.
    func testSDNNAndPNN50AreDeliberatelyNotRoundTripped() throws {
        let source = try demoSource()
        XCTAssertTrue(
            source.contains("hrvSDNNms: hrvNormalized * 90"),
            """
            The demo's SDNN is deliberately NOT anchored to the knob. If this line changed on \
            purpose, update this expectation in the SAME commit and say why — do not delete the \
            check, it is the only thing standing between here and demo SDNN == demo RMSSD.
            """)
        XCTAssertTrue(
            source.contains("hrvPNN50: hrvNormalized * 40"),
            """
            The demo's pNN50 is a percentage and is deliberately NOT anchored to the knob either. \
            Same rule as the SDNN line above: change it on purpose, in the same commit, with a \
            reason.
            """)

        // And the arithmetic half, so the intent is pinned and not just the spelling:
        // a hypothetical ceiling-anchored SDNN would collide with RMSSD exactly.
        let h: Float = 0.5
        XCTAssertNotEqual(
            h * 90, demoRMSSDms(h),
            "Demo SDNN and demo RMSSD must remain distinguishable values.")
    }

    /// COUNTERWEIGHT — green both sides. `BioStripView` blanks the HRV readout for values
    /// outside 3…300 ms. The old range (24…108) and the new one (20…90) both sit inside, so this
    /// is not what the fix repaired — it pins what a DIFFERENT anchor choice would have broken:
    /// a smaller ceiling would have emptied the Demo readout instead of correcting it.
    ///
    /// ⚠️ The band is a HAND COPY. `BioStripView.plausibleHRVms` is `private static`, so nothing
    /// binds these two together — if the strip narrows its window, this test stays green and the
    /// Demo readout goes blank without a red anywhere. Stated rather than papered over.
    func testThePublishedMillisecondsStayInsideTheReadoutBand() {
        let readable: ClosedRange<Float> = 3...300
        for h in [Self.walkBand.lowerBound, 0.5, Self.walkBand.upperBound] {
            let ms = demoRMSSDms(h)
            XCTAssertTrue(
                readable.contains(ms),
                """
                Demo RMSSD \(ms) ms at hrvNormalized \(h) falls outside BioStripView's \
                plausibility band 3…300 ms, so the readout would show "—" for a source whose \
                whole purpose is to give the readouts something to display.
                """)
        }
    }

    // MARK: - Helpers

    private func demoSource() throws -> String {
        let url = try repoRoot()
            .appendingPathComponent("Sources/Echoelmusic/Bio/BioSimulator.swift")
        // Comments stripped through the ONE shared scanner (#453): this file's own prose quotes
        // both `* 120` and `HRVNormalization.ceilingMs`, and the source's ⛔ block quotes `* 120`
        // as the thing it removed — a raw scan would find the retraction and call it the defect.
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
