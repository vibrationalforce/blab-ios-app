// ADMOSCAbsenceTests.swift
// Echoel — #260: what the immersive object does when a channel is NOT measured.
// BLOCKING bundle, because the other suite cannot fail a merge (#208).
//
// THE DEFECT. #245 closed this on the OSC feed and left its twin open one file away.
// `ADMOSCSender.admMessages` derived all three object positions unconditionally, so a frame
// whose channels carry structural zeros produced:
//   · `breathPhase` 0 → azimuth **−180** — the object slammed hard left;
//   · `coherence` 0 → distance **1** — the object pushed to the far end of the room;
//   · `hrvNormalized` 0 → elevation 0 — ear level, the only benign one of the three.
// Two extremes, asserted at 20 Hz, from channels nobody measured. A renderer cannot tell
// that apart from a performer who really is hard left and far away.
//
// ⛔ AND BOTH EXTREMES OCCURRED ON SHIPPING HARDWARE, every session, which is what makes it
// a defect and not a hypothetical:
//   · `PolarH10BioPublisher` publishes `breathRate: 0, breathPhase: 0` on EVERY frame (the
//     strap derives no respiration) and `.ble` is egress-allowed — so a chest-strap take
//     pinned the azimuth at exactly −180 from the first frame to the last;
//   · `CameraRPPGBioPublisher` publishes `coherence: 0` until 16 accepted RR intervals, and
//     `CameraAnalyzer`'s RR series is a fixed 10 s window (≈10 intervals at a resting rate),
//     so on a camera take the distance sat at 1 for the whole session.
// (The first draft of this file blamed `FaceExpressionBioPublisher`'s all-zero frame. That
// was wrong — the type has ZERO instantiations in `Sources/` and sits behind
// `FeatureFlags.cameraExpression`, so no `.faceCam` frame reaches this arm in a shipped
// build. Recorded rather than quietly swapped, because the corrected path is the stronger
// one and the wrong one had already been copied from `OSCSender`.)
//
// THE RULE, identical to the OSC side: every address rides its OWN channel's measurement,
// and silence means "not measured", never "measured as zero". ADM-OSC renderers hold their
// last value, so an omitted address leaves the object where it is — which is what a slipped
// finger should look like.
//
// ⚠️ WHAT THIS FILE DOES NOT COVER. It pins the pure mapping. That `sendIfFresh` actually
// puts these on a socket, and that it no longer stamps `lastSentTimestamp` for a tick with
// nothing to send, need a live `NWConnection` and are not observable here.

#if canImport(Network)
import Foundation
import XCTest
@testable import Echoelmusic

final class ADMOSCAbsenceTests: XCTestCase {
    // `ADMOSCSender` is `@MainActor`, but `admMessages` is `nonisolated static` — the same
    // shape as `OSCSender.bioMessages` and `ADMOSCSender.motionGain`, and the reason this
    // class needs no `@MainActor` of its own. If a future edit drops that annotation, this
    // file stops compiling and takes the merge gate with it.

    private func frame(bpm: Float, hrv: Float = 0, breath: Float = 0,
                       phase: Float = 0, coherence: Float = 0) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: bpm, hrvNormalized: hrv,
                       breathRate: breath, breathPhase: phase, coherence: coherence,
                       motionEnergy: 0, source: .cameraPPG)
    }

    /// ⛔ POSITION ADDRESSES ONLY — and that filter is the point, not a convenience. This
    /// file is about the three POSITION axes. `/gain` rides a different gate
    /// (`ModSource.motion.hasProducer`, #215) which is false today and will one day be true;
    /// an exact-match assertion over ALL addresses would then redden the BLOCKING bundle on
    /// the commit that adds a motion sensor — punishing the right change for the wrong
    /// reason. `OSCAbsenceTests` learned this one commit earlier; this file was written
    /// without the lesson and is corrected here.
    private func addresses(_ f: BioSampleFrame) -> [String] {
        ADMOSCSender.admMessages(for: f, object: 1)
            .map { $0.0 }
            .filter { $0.contains("/position/") }
    }

    /// ⛔ THE ASSERTION THE SLICE EXISTS FOR. This is the `FaceExpressionBioPublisher`
    /// frame: egress-allowed, entirely unmeasured. Before the fix it parked the object hard
    /// left at maximum distance; now it says nothing at all.
    func testAnEntirelyUnmeasuredFrameMovesNoObject() {
        XCTAssertEqual(addresses(frame(bpm: 0)), [],
                       "an all-zero bio frame still drives the immersive object — hard left "
                       + "at full distance, which no renderer can tell from a real position")
    }

    /// The three positions come from three DIFFERENT channels, so each must be able to
    /// arrive alone: a respiration reading pans the object without also claiming a height,
    /// and a strap that has locked a pulse and an HRV lifts it without panning it to the
    /// wall — which is exactly the strap case, since `PolarH10BioPublisher` never reports
    /// breath at all.
    func testEachChannelCarriesOnlyItsOwnAddress() {
        XCTAssertEqual(addresses(frame(bpm: 62, breath: 12, phase: 0.25)),
                       ["/adm/obj/1/position/azimuth"],
                       "breath alone must not also assert elevation or distance")
        XCTAssertEqual(addresses(frame(bpm: 62, hrv: 0.4)),
                       ["/adm/obj/1/position/elevation"],
                       "HRV alone must not also assert azimuth or distance")
        XCTAssertEqual(addresses(frame(bpm: 62, coherence: 0.7)),
                       ["/adm/obj/1/position/distance"],
                       "coherence alone must not also assert azimuth or elevation")
    }

    /// ⛔ THE ONE THAT COST THE OSC SIDE A RED GATE (#245): the sentinel alone is not
    /// enough. A non-zero HRV or coherence sitting beside a pulse of 0 is a publisher bug,
    /// not a reading, and forwarding it puts an invented position in someone else's rig.
    func testAMalformedFrameWithNoPulseIsRefusedEvenWhereItLooksMeasured() {
        XCTAssertEqual(addresses(frame(bpm: 0, hrv: 0.9, coherence: 0.9)), [],
                       "a heart-derived position escaped without a heart rate")
    }

    /// Breath is gated on the RATE, not on the phase — `breathPhase` has no unknown
    /// sentinel, 0 is a real position (exhale start), so it cannot answer for itself. A
    /// phase of 0 beside a plausible rate is therefore a genuine hard-left reading and MUST
    /// still be sent; the same 0 without a rate must not.
    func testTheHardLeftPositionIsSentWhenItIsRealAndWithheldWhenItIsNot() throws {
        let real = ADMOSCSender.admMessages(for: frame(bpm: 62, breath: 12, phase: 0),
                                            object: 1)
        let azimuth = try XCTUnwrap(real.first { $0.0.hasSuffix("/position/azimuth") }?.1)
        XCTAssertEqual(azimuth, -180, accuracy: 0.001,
                       "a measured exhale-start really is hard left — the gate must not "
                       + "swallow the reading it exists to distinguish")
        XCTAssertEqual(addresses(frame(bpm: 62, breath: 0, phase: 0)), [],
                       "and the identical phase without a breath rate is an absence")
    }

    /// Breath outside the plausible band is an absence, not a reading — you cannot breathe
    /// zero or ninety times a minute. Shares `BioSampleFrame.plausibleBreathRate` with the
    /// OSC path rather than restating a band that could drift apart from it.
    func testAnImplausibleBreathRateIsTreatedAsNoBreathAtAll() {
        let band = BioSampleFrame.plausibleBreathRate
        for rate: Float in [band.lowerBound - 1, band.upperBound + 1] {
            XCTAssertEqual(addresses(frame(bpm: 62, breath: rate, phase: 0.5)), [],
                           "breath rate \(rate) is outside \(band) and must not position "
                           + "the object")
        }
        XCTAssertFalse(addresses(frame(bpm: 62, breath: band.lowerBound, phase: 0.5)).isEmpty,
                       "the band's own edge is a reading, or the gate is stricter than the "
                       + "constant it claims to use")
    }

    /// ⛔ THE ONE AXIS A CORRUPT VALUE CAN STILL REACH. `hrvNormalized > 0` and
    /// `coherence > 0` are both false for NaN, so those two self-refuse; but `3...40` can
    /// hold a perfectly real breath RATE beside a corrupt PHASE, and this file's `clamp` is
    /// the `min(max(…))` form that passes NaN straight through (CLAUDE.md's argument-order
    /// rule). So the azimuth gate carries an explicit `isFinite`.
    ///
    /// ⚠️ `isFinite` REFUSES BOTH NaN AND ±INFINITY, and the first version of this test got
    /// that wrong — it asserted that an infinite phase "is clampable and must still be
    /// sent", which is what CI failed on. Recorded rather than quietly corrected, because
    /// the mistake was reading my own gate as `!isNaN`: an infinite breath phase is not a
    /// clamped reading, it is a corrupt one, and the honest answer for a corrupt input on
    /// this arm is the same as for an absent one — say nothing.
    func testANonFiniteBreathPhaseIsNotAPosition() {
        for bad: Float in [.nan, .infinity, -.infinity] {
            XCTAssertEqual(addresses(frame(bpm: 62, breath: 12, phase: bad)), [],
                           "breath phase \(bad) left the device as an azimuth")
        }
        // …and the same rate with a REAL phase still positions, or the loop above would
        // pass for the wrong reason (a breath gate that stopped working entirely).
        XCTAssertEqual(addresses(frame(bpm: 62, breath: 12, phase: 0.75)),
                       ["/adm/obj/1/position/azimuth"])
    }

    /// ANTI-VACUITY. Every assertion above is about ABSENCE, so a mapping that returned
    /// nothing at all would pass the whole file. A fully measured frame must still produce
    /// the complete position set.
    func testAFullyMeasuredFrameStillPositionsTheObject() {
        let full = frame(bpm: 62, hrv: 0.5, breath: 12, phase: 0.5, coherence: 0.7)
        XCTAssertEqual(addresses(full), [
            "/adm/obj/1/position/azimuth",
            "/adm/obj/1/position/elevation",
            "/adm/obj/1/position/distance"
        ], "a measured body must still drive all three axes")
    }
}
#endif
