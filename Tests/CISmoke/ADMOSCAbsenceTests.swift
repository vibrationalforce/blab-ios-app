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
// ⛔ AND IT WAS REACHABLE IN A SHIPPED CONFIGURATION, which is what makes it a defect and
// not a hypothetical: `FaceExpressionBioPublisher` emits an all-zero bio frame and its
// source is on `BioEgressPolicy`'s allow-list, so `sendIfFresh` forwards it. The camera and
// strap publishers both require a plausible pulse before publishing, but neither guarantees
// breath or coherence — coherence needs 16 accepted RR intervals and a camera take may
// never reach that at all (`HRVCoherence.minIntervals`, and the note in `OSCSender`).
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

    private func frame(bpm: Float, hrv: Float = 0, breath: Float = 0,
                       phase: Float = 0, coherence: Float = 0) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: bpm, hrvNormalized: hrv,
                       breathRate: breath, breathPhase: phase, coherence: coherence,
                       motionEnergy: 0, source: .cameraPPG)
    }

    private func addresses(_ f: BioSampleFrame) -> [String] {
        ADMOSCSender.admMessages(for: f, object: 1).map { $0.0 }
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
    /// arrive alone. A strap that has locked a pulse and an HRV but no respiration lifts the
    /// object without also panning it to the wall.
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
