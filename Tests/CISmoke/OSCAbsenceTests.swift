// OSCAbsenceTests.swift
// Echoel — #245: on the wire, a 0 is a VALUE. Silence is the only form the protocol has for
// "I do not know". BLOCKING bundle, because the other suite cannot fail a merge (#208).
//
// WHAT WENT WRONG. `/bio/heart/bpm`, `/hrv`, `/breath/rate`, `/breath/phase` and `/coherence`
// were sent on EVERY frame, structural zeros included. Downstream that is not a gap, it is a
// measurement: a VJ's bound scale collapses, a lighting desk slews its Grand Master to black,
// and neither can tell that apart from a performer who really stopped. #215 had already decided
// exactly this for `/bio/motion` — further down the SAME function, and the other five were
// simply never revisited.
//
// ⚠️ WHICH FRAMES ACTUALLY TRIGGER IT — corrected in review, because the first version of this
// header named a mechanism that does not exist. It said "the frames a publisher emits before it
// locks and after a finger lifts". Neither live pulse sensor emits those: `CameraRPPGBioPublisher`
// requires `bpm > 0` to publish at all, and `PolarH10BioPublisher` requires a plausible BPM. The
// THREE REAL cases are (a) `FaceExpressionBioPublisher`, which publishes an all-zero bio frame
// and IS egress-allowed; (b) the ~55 s at the start of every session where a LOCKED pulse sits
// next to `hrvNormalized == 0` and `coherence == 0`, because both are derived from the beat
// series and the RR record is not yet long enough for a spectrum; and (c) a MALFORMED frame —
// non-zero HRV or coherence beside `bpm == 0`, which is physically impossible and means a
// publisher bug, not a reading to forward.
//
// ⛔ (b) AND (c) PULL IN OPPOSITE DIRECTIONS, and this file got it wrong in each direction once,
// in consecutive commits. A pulse-only gate passes (c) and fails (b); a sentinel-only gate passes
// (b) and fails (c) — CI caught the second one here. `/hrv` and `/coherence` therefore need BOTH:
// a real pulse AND a non-zero sentinel. Neither half is redundant.
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
                       coherence: Float = 0.7, rmssd: Float = 0, sdnn: Float = 0,
                       pnn50: Float = 0) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: bpm, hrvNormalized: hrv,
                       breathRate: breath, breathPhase: phase, coherence: coherence,
                       motionEnergy: 0, source: .cameraPPG,
                       hrvRMSSDms: rmssd, hrvSDNNms: sdnn, hrvPNN50: pnn50)
    }

    private func addresses(_ f: BioSampleFrame) -> Set<String> {
        Set(OSCSender.bioMessages(for: f).map(\.address))
    }

    /// ⛔ THE ASSERTION THE SLICE EXISTS FOR. No pulse → not one heart-derived address on the
    /// wire, INCLUDING when the frame carries non-zero HRV/coherence/RMSSD/SDNN/pNN50 beside
    /// `bpm == 0`.
    ///
    /// ⚠️ THAT LAST CLAUSE IS THE POINT, and CI had to teach it (`33876a0` went red here). The
    /// fixture's defaults are hrv 0.5 / coherence 0.7, so this frame is MALFORMED: both are
    /// derived from the beat series and cannot exist without a pulse. When the gates were briefly
    /// sentinel-only, those two went out — an invented number on someone else's lighting desk,
    /// sourced from a publisher bug. The fixture is left deliberately malformed rather than
    /// "corrected", because a frame nobody should ever build is exactly what an egress must
    /// refuse: the defensive half of the gate has no other way to be tested.
    ///
    /// All FIVE are asserted, not the three that were red. The time-domain trio was still on a
    /// bare sentinel after `/hrv` and `/coherence` gained the precondition, and RMSSD/pNN50/SDNN
    /// are the most beat-derived numbers in the frame — statistics over the NN series. A rule
    /// that two of five heart addresses follow reads as arbitrary and gets tidied away.
    func testAFrameWithoutAPulseSendsNoHeartDerivedAddress() {
        let sent = addresses(frame(bpm: 0, breath: 0, rmssd: 42, sdnn: 55, pnn50: 0.3))
        for address in ["/echoelmusic/bio/heart/bpm",
                        "/echoelmusic/bio/heart/hrv",
                        "/echoelmusic/bio/heart/rmssd",
                        "/echoelmusic/bio/heart/pnn50",
                        "/echoelmusic/bio/heart/sdnn",
                        "/echoelmusic/bio/coherence"] {
            XCTAssertFalse(sent.contains(address),
                           "\(address) went out on a frame with no measured pulse. On the wire "
                           + "that 0 is a measurement: a bound scale collapses and a lighting "
                           + "desk goes black, with nothing in the protocol saying the sensor "
                           + "simply has not locked yet.")
        }
    }

    /// And the un-measured frame must be SILENT, not merely thinned — otherwise a receiver still
    /// sees traffic and reads the missing addresses as "unchanged" rather than "absent". Same
    /// malformed fixture as above, for the same reason: with sentinel-only gates this produced
    /// two messages and went red on CI, which is how the missing precondition was found.
    func testAFrameWithNothingMeasuredSendsNothingAtAll() {
        XCTAssertTrue(OSCSender.bioMessages(for: frame(bpm: 0, breath: 0)).isEmpty,
                      "a frame carrying no measurement at all still produced messages: "
                      + "\(OSCSender.bioMessages(for: frame(bpm: 0, breath: 0)).map(\.address))")
    }

    /// ⭐ BREATH RIDES ITS OWN GATE — but NOT because the two signals are independently produced.
    /// That was this comment's first claim and it is false for the only egress-allowed source that
    /// carries breath: `CameraRPPGBioPublisher` derives respiration from the RR series via RSA, so
    /// no pulse means no breath. HealthKit IS independent and is network-blocked upstream (5.1.3).
    /// The separate gate is kept because it is defensively right and free, and because the day an
    /// independent producer arrives nothing has to be remembered — but it buys no live case today,
    /// and this test pins a state no shipping publisher can currently reach. Said plainly so the
    /// coverage is not overread.
    func testBreathSurvivesAFrameWithNoPulse() {
        let sent = addresses(frame(bpm: 0, breath: 12))
        XCTAssertTrue(sent.contains("/echoelmusic/bio/breath/rate"))
        XCTAssertTrue(sent.contains("/echoelmusic/bio/breath/phase"))
        XCTAssertFalse(sent.contains("/echoelmusic/bio/heart/bpm"))
    }

    /// ⛔ AND THE TRAP IN THE OTHER DIRECTION: `breathPhase` may NEVER gate on its own value.
    /// 0 is a legitimate phase — EXHALE start, per the field's own doc (0.5 is inhale start) —
    /// so a `> 0` test there would drop real data once per breath cycle, which is a worse defect
    /// than the fabrication it would prevent. This is the assertion that catches someone "tidying"
    /// the gates into one uniform rule.
    ///
    /// ⚠️ THIS COMMENT SAID "the start of an inhale" IN ITS FIRST VERSION, in six places at once,
    /// which is backwards. The decision was right and the physiology stated for it was inverted —
    /// a rationale nobody can check against the field it describes is how a correct rule gets
    /// "corrected" away later.
    func testPhaseZeroIsSentBecauseZeroIsARealPhase() {
        let sent = addresses(frame(bpm: 60, breath: 12, phase: 0))
        XCTAssertTrue(sent.contains("/echoelmusic/bio/breath/phase"),
                      "phase 0 was dropped. It is EXHALE START, not an absence — "
                      + "gate the phase on the RATE, never on itself.")
    }

    /// A fully measured frame must still send everything it used to, or the gate has become a
    /// silence bug. Pinned because every assertion above is about NOT sending, and a mistake that
    /// sends nothing at all would satisfy all of them.
    func testAFullyMeasuredFrameStillSendsTheWholeSet() {
        let sent = addresses(frame(bpm: 62, breath: 11, rmssd: 42, sdnn: 55, pnn50: 0.3))
        for address in ["/echoelmusic/bio/heart/bpm",
                        "/echoelmusic/bio/heart/hrv",
                        "/echoelmusic/bio/heart/rmssd",
                        "/echoelmusic/bio/heart/pnn50",
                        "/echoelmusic/bio/heart/sdnn",
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

    /// ⭐ THE CASE THE FIRST CUT OF THIS SLICE MISSED, and the one that actually bites in a show:
    /// a LOCKED pulse with no HRV and no coherence yet. Both are derived from the beat SERIES, so
    /// `PolarH10BioPublisher` and `CameraRPPGBioPublisher` publish a real BPM alongside a 0 for
    /// each of them for roughly the first 55 s of a session, and again whenever the RR record is
    /// untrustworthy. Putting those two on the PULSE gate — which is what the first version did —
    /// let the collapse-to-zero straight through on the two addresses a lighting desk is most
    /// likely bound to. Both fields carry their own sentinel and both of their docs say so.
    func testALockedPulseWithoutHRVSendsNeitherHRVNorCoherence() {
        let sent = addresses(frame(bpm: 64, hrv: 0, breath: 12, coherence: 0))
        XCTAssertTrue(sent.contains("/echoelmusic/bio/heart/bpm"),
                      "the pulse IS measured here and must still be sent")
        XCTAssertFalse(sent.contains("/echoelmusic/bio/heart/hrv"),
                       "hrv 0 went out next to a locked pulse. Its own doc says 0 means NOT "
                       + "MEASURED, never 'minimum variability' — this is the first ~55 s of "
                       + "EVERY session, not an edge case.")
        XCTAssertFalse(sent.contains("/echoelmusic/bio/coherence"),
                       "coherence 0 went out next to a locked pulse. Its own doc says treat 0 as "
                       + "'not available', not as 'incoherent'.")
    }

    /// The hoisted predicates, pinned where they live (#244). ⚠️ `hasMeasuredBreath` is the
    /// PLAUSIBILITY BAND (3…40/min), not a bare `> 0` — you cannot breathe half a time a minute.
    /// The first cut of this slice declared a SECOND `hasMeasuredBreath` as `breathRate > 0`
    /// beside the existing one: a redeclaration that did not compile, and that would have admitted
    /// an implausible rate if it had. Both bounds are asserted so the band cannot quietly widen.
    func testTheMeasuredPredicatesMeanWhatTheirNamesSay() {
        XCTAssertFalse(frame(bpm: 0, breath: 0).hasMeasuredHeartRate)
        XCTAssertTrue(frame(bpm: 40, breath: 0).hasMeasuredHeartRate)
        XCTAssertFalse(frame(bpm: 60, breath: 0).hasMeasuredBreath)
        XCTAssertTrue(frame(bpm: 60, breath: 4).hasMeasuredBreath)
        XCTAssertFalse(frame(bpm: 60, breath: 0.5).hasMeasuredBreath,
                       "half a breath per minute passed the gate — that is an absence, not a "
                       + "reading, and a bare `> 0` would have let it through")
        XCTAssertFalse(frame(bpm: 60, breath: 60).hasMeasuredBreath,
                       "60 breaths per minute passed the gate — the band has an upper bound too")
    }
}
