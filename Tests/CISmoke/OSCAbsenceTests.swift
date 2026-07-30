// OSCAbsenceTests.swift
// Echoel — #245: on the wire, a 0 is a VALUE. Silence is the only form the protocol has for
// "I do not know". BLOCKING bundle, because the other suite cannot fail a merge (#208).
//
// WHAT WENT WRONG. `/bio/heart/bpm`, `/hrv`, `/breath/rate`, `/breath/phase` and `/coherence`
// were sent on EVERY frame, including the frames a publisher emits before it locks and after a
// finger lifts, where `heartRateBPM` is a structural 0. Downstream that is not a gap, it is a
// measurement: a VJ's bound scale collapses, a lighting desk slews its Grand Master to black,
// and neither can tell that apart from a performer who really stopped. #215 had already fixed
// exactly this for `/bio/motion` — eighteen lines further down the SAME function.
//
// It is not an edge case either. Device log 2476 (#235) published ONE frame in 110 s of an
// otherwise locked pulse, so today the un-measured state is the common one.
//
// ⚠️ WHAT THIS FILE DOES NOT COVER. It pins the pure message list, not the socket: whether a
// datagram leaves the device, whether `BioEgressPolicy` allows the source, and whether the
// ~10 Hz caller runs at all are separate paths with their own tests. Stated so "OSC is tested"
// is not read into it.

import Foundation
import XCTest
@testable import Echoelmusic

final class OSCAbsenceTests: XCTestCase {

    private func frame(bpm: Float, hrv: Float = 0.5, breath: Float, phase: Float = 0.25,
                       coherence: Float = 0.7) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: bpm, hrvNormalized: hrv,
                       breathRate: breath, breathPhase: phase, coherence: coherence,
                       motionEnergy: 0, source: .camera)
    }

    private func addresses(_ f: BioSampleFrame) -> Set<String> {
        Set(OSCSender.bioMessages(for: f).map(\.address))
    }

    /// ⛔ THE ASSERTION THE SLICE EXISTS FOR. No pulse → not one heart-derived address on the
    /// wire. Written as a Set difference rather than a count so a future address added under the
    /// same gate is covered automatically, and one added OUTSIDE it fails loudly.
    func testAFrameWithoutAPulseSendsNoHeartDerivedAddress() {
        let sent = addresses(frame(bpm: 0, breath: 0))
        for address in ["/echoelmusic/bio/heart/bpm",
                        "/echoelmusic/bio/heart/hrv",
                        "/echoelmusic/bio/coherence"] {
            XCTAssertFalse(sent.contains(address),
                           "\(address) went out on a frame with no measured pulse. On the wire "
                           + "that 0 is a measurement: a bound scale collapses and a lighting "
                           + "desk goes black, with nothing in the protocol saying the sensor "
                           + "simply has not locked yet.")
        }
    }

    /// And the un-measured frame must be SILENT, not merely thinned — otherwise a receiver still
    /// sees traffic and reads the missing addresses as "unchanged" rather than "absent".
    func testAFrameWithNothingMeasuredSendsNothingAtAll() {
        XCTAssertTrue(OSCSender.bioMessages(for: frame(bpm: 0, breath: 0)).isEmpty,
                      "a frame carrying no measurement at all still produced messages: "
                      + "\(OSCSender.bioMessages(for: frame(bpm: 0, breath: 0)).map(\.address))")
    }

    /// ⭐ BREATH RIDES ITS OWN GATE. The two signals are independently produced, so a frame with
    /// breath but no pulse must still deliver breath — gating everything on the pulse would have
    /// been the easy fix and would have silently dropped a working channel.
    func testBreathSurvivesAFrameWithNoPulse() {
        let sent = addresses(frame(bpm: 0, breath: 12))
        XCTAssertTrue(sent.contains("/echoelmusic/bio/breath/rate"))
        XCTAssertTrue(sent.contains("/echoelmusic/bio/breath/phase"))
        XCTAssertFalse(sent.contains("/echoelmusic/bio/heart/bpm"))
    }

    /// ⛔ AND THE TRAP IN THE OTHER DIRECTION: `breathPhase` may NEVER gate on its own value.
    /// 0 is a legitimate phase — the start of an inhale — so a `> 0` test there would drop real
    /// data once per breath cycle, which is a worse defect than the fabrication it would prevent.
    /// This is the assertion that catches someone "tidying" the gates into one uniform rule.
    func testPhaseZeroIsSentBecauseZeroIsARealPhase() {
        let sent = addresses(frame(bpm: 60, breath: 12, phase: 0))
        XCTAssertTrue(sent.contains("/echoelmusic/bio/breath/phase"),
                      "phase 0 was dropped. It is the START OF AN INHALE, not an absence — "
                      + "gate the phase on the RATE, never on itself.")
    }

    /// A fully measured frame must still send everything it used to, or the gate has become a
    /// silence bug. Pinned because every assertion above is about NOT sending, and a mistake that
    /// sends nothing at all would satisfy all of them.
    func testAFullyMeasuredFrameStillSendsTheWholeSet() {
        let sent = addresses(frame(bpm: 62, breath: 11))
        for address in ["/echoelmusic/bio/heart/bpm",
                        "/echoelmusic/bio/heart/hrv",
                        "/echoelmusic/bio/breath/rate",
                        "/echoelmusic/bio/breath/phase",
                        "/echoelmusic/bio/coherence"] {
            XCTAssertTrue(sent.contains(address),
                          "\(address) is missing from a frame where everything IS measured — "
                          + "the absence gate has turned into a silence bug")
        }
        XCTAssertFalse(sent.contains("/echoelmusic/bio/motion"),
                       "motion came back. Nothing measures it (#215); its gate is structural, "
                       + "not value-based, and it stays off until a producer exists.")
    }

    /// The predicate itself, pinned where the hoist lives (#244). Five call sites wrote
    /// `heartRateBPM > 0` by hand before this property existed, which is how the sixth consumer —
    /// this OSC egress — came to be written WITHOUT it.
    func testTheMeasuredPredicatesMeanWhatTheirNamesSay() {
        XCTAssertFalse(frame(bpm: 0, breath: 0).hasMeasuredHeartRate)
        XCTAssertTrue(frame(bpm: 40, breath: 0).hasMeasuredHeartRate)
        XCTAssertFalse(frame(bpm: 60, breath: 0).hasMeasuredBreath)
        XCTAssertTrue(frame(bpm: 60, breath: 4).hasMeasuredBreath)
    }
}
