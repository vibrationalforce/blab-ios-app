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
// ⛔ HONEST ABOUT WHICH CLAIMS CAN FAIL, because I have mis-filed my own tests before (#433):
//   · `testTheKnobRoundTripsThroughTheSharedCeiling`  — REGRESSION. On `*120` it is red at every
//     sampled point (measured +20 % flat).
//   · `testTheDemoChainsToTheCeilingInsteadOfCopyingIt` — REGRESSION. The old source held the
//     literal `* 120` and never named `HRVNormalization`.
//   · `testSDNNAndPNN50AreDeliberatelyNotRoundTripped` — COUNTERWEIGHT. Green before AND after.
//     It exists so the symmetrical-looking "tidy-up" (give SDNN the same ceiling) turns red
//     instead of silently making demo SDNN identical to demo RMSSD.
//   · `testTheCeilingIsTheOneHouseCeiling`             — PREMISE. Green both sides. Without it
//     this file could drift from the app's converter and keep passing on its own arithmetic.
//   · `testThePublishedMillisecondsStayInsideTheReadoutBand` — COUNTERWEIGHT. Green both sides
//     (24…108 was inside too). It pins the thing a *different* anchor choice would have broken:
//     `BioStripView` blanks the HRV readout outside 3…300 ms, so a fix that anchored to a small
//     ceiling would have silently emptied the Demo readout rather than corrected it.
//
// ⭐ THE DEFECT. `HRVNormalization` exists because #97 found three live sources each carrying
// their OWN divisor for the SAME `hrvNormalized` field (camera ÷200, strap ÷100, HealthKit ÷100).
// It collapsed them onto one 100 ms ceiling. The DEMO source was not in that audit and kept a
// fourth divisor — 120 for RMSSD — so the frame it published was internally unreconcilable: at
// `hrvNormalized` 0.5 it shipped 60 ms, while the app's own rule says 60 ms is 0.60.
//
// ⚠️ THE INVARIANT IS SOURCE-DEPENDENT AND THAT IS WHY THE ANCHOR IS RMSSD. On camera and Polar
// the knob is `normalize(rmssd)`; on HealthKit it is `normalize(sdnn)`, because HealthKit has no
// beat-to-beat RR. The demo publishes RMSSD *and* pNN50 — quantities only an RR source has — so
// it belongs to the RR convention. Anchoring it on SDNN would have been a third rule.
//
// ⚠️ NOT PROVEN HERE: that any of this is visible or audible. The two consumers of
// `hrvRMSSDms` are the OSC egress (`/echoelmusic/bio/heart/rmssd`) and `BioStripView`'s readout;
// whether a lighting desk or a founder ever looks at the demo's number is a device question.
// The arithmetic is wrong either way, which is why it is fixed rather than deferred.

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

    // MARK: - Regressions

    /// REGRESSION. Every point of the walk band must survive the app's own ms→knob converter
    /// unchanged. On the shipped `* 120` this failed at every sampled point by a flat +20 %.
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
        // exact division by the ceiling, so only representation error may remain.
        XCTAssertLessThan(
            worstAbsolute, 1e-6,
            "The Demo source publishes an RMSSD its own hrvNormalized contradicts. Worst "
            + "disagreement \(worstAbsolute) at hrvNormalized \(worstAt). On every real source "
            + "hrvNormalized == HRVNormalization.normalize(<that source's ms metric>) exactly; "
            + "the demo must not be the one source where recomputing the knob from the wire "
            + "value gives a different number.")
    }

    /// REGRESSION. The demo must READ the house ceiling, not restate a number that happens to
    /// equal it. A literal `100` here would pass the arithmetic test above and re-open the exact
    /// defect the day someone retunes `HRVNormalization.ceilingMs` (#416 form).
    func testTheDemoChainsToTheCeilingInsteadOfCopyingIt() throws {
        let source = try demoSource()
        XCTAssertTrue(
            source.contains("HRVNormalization.ceilingMs"),
            "BioSimulator must derive its RMSSD from HRVNormalization.ceilingMs. A restated "
            + "literal is the #97 copy-drift defect with a correct value today.")
        XCTAssertFalse(
            source.contains("* 120"),
            "BioSimulator still holds the fourth divisor (* 120) that #97 removed from the "
            + "three live sources.")
    }

    // MARK: - Counterweights and premises

    /// COUNTERWEIGHT — green before and after. The tidy-up that looks like consistency is to
    /// give SDNN the same ceiling. It is not consistency: on camera and Polar SDNN does not
    /// round-trip either (the knob is anchored on RMSSD there too), and doing it here would make
    /// the demo's SDNN bit-identical to its RMSSD — a pair no body produces, and one that makes
    /// the Demo source useless for testing a receiver that plots the two separately.
    func testSDNNAndPNN50AreDeliberatelyNotRoundTripped() throws {
        let source = try demoSource()
        XCTAssertTrue(
            source.contains("hrvSDNNms: hrvNormalized * 90"),
            "The demo's SDNN is deliberately NOT anchored to the knob. If this line changed on "
            + "purpose, update this expectation in the SAME commit and say why — do not delete "
            + "the check, it is the only thing standing between here and demo SDNN == demo "
            + "RMSSD.")

        // And the arithmetic half, so the intent is pinned and not just the spelling:
        // a hypothetical ceiling-anchored SDNN would collide with RMSSD exactly.
        let h: Float = 0.5
        XCTAssertNotEqual(
            h * 90, demoRMSSDms(h),
            "Demo SDNN and demo RMSSD must remain distinguishable values.")
    }

    /// PREMISE — green both sides. Binds this file's arithmetic to the app's converter, so the
    /// guard cannot drift into testing its own private idea of normalization.
    func testTheCeilingIsTheOneHouseCeiling() {
        XCTAssertEqual(HRVNormalization.ceilingMs, 100.0, accuracy: 1e-12,
                       "The shared HRV ceiling moved. That is allowed — but every source, "
                       + "including the Demo generator, must move with it.")
        // `normalize` must be plain division below the ceiling; the round-trip proof rests on it.
        XCTAssertEqual(HRVNormalization.normalize(50), 0.5, accuracy: 1e-12)
        XCTAssertEqual(HRVNormalization.normalize(250), 1.0, accuracy: 1e-12, "clamps at the top")
        XCTAssertEqual(HRVNormalization.normalize(0), 0.0, accuracy: 1e-12, "0 = no usable HRV")
    }

    /// COUNTERWEIGHT — green both sides. `BioStripView` blanks the HRV readout for values
    /// outside 3…300 ms. The old range (24…108) and the new one (20…90) both sit inside, so this
    /// is not what the fix repaired — it pins what a DIFFERENT anchor choice would have broken:
    /// a smaller ceiling would have emptied the Demo readout instead of correcting it.
    func testThePublishedMillisecondsStayInsideTheReadoutBand() {
        let readable: ClosedRange<Float> = 3...300
        for h in [Self.walkBand.lowerBound, 0.5, Self.walkBand.upperBound] {
            let ms = demoRMSSDms(h)
            XCTAssertTrue(
                readable.contains(ms),
                "Demo RMSSD \(ms) ms at hrvNormalized \(h) falls outside BioStripView's "
                + "plausibility band 3…300 ms, so the readout would show \"—\" for a source "
                + "whose whole purpose is to give the readouts something to display.")
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
            throw XCTSkip("source tree not present at \(sources.path) — this test inspects "
                          + "source text, so it SKIPS rather than reporting a green it did "
                          + "not earn")
        }
        return root
    }
}
