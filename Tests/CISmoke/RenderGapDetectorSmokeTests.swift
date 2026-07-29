// RenderGapDetectorSmokeTests.swift
// Echoel — the rule that decides whether "es knistert" gets a number or another guess.
//
// WHY IT IS IN CISmoke, since this bundle must not become a dumping ground: it is the
// BLOCKING bundle (`project.yml`'s `EchoelmusicTests` target sources only this directory;
// everything under `Tests/EchoelmusicTests` runs in a workflow whose build step carries
// `continue-on-error` — #208). Note the corollary: `Package.swift` points its test target
// at `Tests/EchoelmusicTests`, so `swift test` never compiles this file — only the Xcode
// gate does. Two reasons this one earns a gate:
//
//   1. The thing under test is the INSTRUMENT for a live founder defect (#193). An
//      instrument that silently reports nonsense is worse than none — it would end the
//      search rather than direct it. That is the same class `doctor` exists for.
//   2. I shipped a test one cycle ago that could not pass, in the non-blocking suite, and
//      nothing told me. A threshold rule that decides what goes into the founder's
//      diagnostics file should not depend on my arithmetic being right unwatched.
//
// Pure `Double` arithmetic — no audio, no device, no clock, microseconds to run.

import XCTest
@testable import Echoelmusic

final class RenderGapDetectorSmokeTests: XCTestCase {

    // The shipping geometry: the meter tap is installed at 1024 frames while the IO
    // buffer is 512 (`AudioConfiguration.currentBufferSize`) — 21.33 ms of tap period
    // built out of two 10.67 ms render deadlines. Every test below uses BOTH numbers on
    // purpose; the gap between them is where the interesting mistake lives.
    private let tapFrames = 1024
    private let quantumFrames = 512
    private let rate: Double = 48_000
    private var tapPeriod: Double { Double(tapFrames) / rate }
    private var quantum: Double { Double(quantumFrames) / rate }

    private func report(elapsed: Double) -> RenderGapReport {
        RenderGapDetector.compare(elapsedSeconds: elapsed, frames: tapFrames,
                                  sampleRate: rate, renderQuantumFrames: quantumFrames)
    }

    // MARK: - The measurement

    /// On-time and early intervals are not lateness. Early matters: CoreAudio delivers
    /// taps in bursts, so a short interval is normal and must never register as negative
    /// lateness that a later `max()` would then treat as the best case.
    func testAnOnTimeOrEarlyIntervalIsNotLate() {
        for elapsed in [tapPeriod, tapPeriod * 0.5, 0.0] {
            let r = report(elapsed: elapsed)
            XCTAssertEqual(r.lateBySeconds, 0, accuracy: 1e-12, "elapsed \(elapsed)")
            XCTAssertFalse(RenderGapDetector.isGlitch(r))
        }
    }

    /// Lateness is measured against the TAP period but REPORTED in render quanta — the
    /// unit in which "one missed deadline" equals 1.
    func testLatenessIsReportedInRenderQuanta_notTapPeriods() {
        let r = report(elapsed: tapPeriod + quantum * 2)
        XCTAssertEqual(r.lateBySeconds, quantum * 2, accuracy: 1e-9)
        XCTAssertEqual(r.lateInQuanta, 2, accuracy: 1e-9,
                       "two render deadlines late — which is only ONE extra tap period")
        XCTAssertEqual(r.expectedPeriodSeconds, tapPeriod, accuracy: 1e-12)
        XCTAssertEqual(r.quantumSeconds, quantum, accuracy: 1e-12)
    }

    /// Same lateness in quanta must read the same at a different rate and buffer size —
    /// otherwise the threshold below means different things on different hardware, and a
    /// media-services reset can change the rate mid-session (#212).
    func testTheScaleFreeNumberIsIndependentOfRateAndBufferSize() {
        let a = RenderGapDetector.compare(elapsedSeconds: (1024.0 / 48_000) + (512.0 / 48_000) * 1.5,
                                          frames: 1024, sampleRate: 48_000,
                                          renderQuantumFrames: 512)
        let b = RenderGapDetector.compare(elapsedSeconds: (512.0 / 44_100) + (256.0 / 44_100) * 1.5,
                                          frames: 512, sampleRate: 44_100,
                                          renderQuantumFrames: 256)
        XCTAssertEqual(a.lateInQuanta, b.lateInQuanta, accuracy: 1e-9)
        XCTAssertEqual(a.lateInQuanta, 1.5, accuracy: 1e-9)
    }

    // MARK: - The threshold

    /// THE RULE THE DIAGNOSTICS FILE DEPENDS ON, and the reason the quantum unit exists.
    /// A single missed render deadline delays a 1024-frame tap by only HALF a tap period.
    /// A threshold denominated in tap periods would need TWO consecutive misses to fire —
    /// blind to exactly the event that makes one audible crackle.
    func testOneMissedRenderDeadlineIsCaught_thoughItIsOnlyHalfATapPeriod() {
        let missed = report(elapsed: tapPeriod + quantum)
        XCTAssertEqual(missed.lateBySeconds / missed.expectedPeriodSeconds, 0.5, accuracy: 1e-9,
                       "half a TAP period — the number a tap-denominated rule would see")
        XCTAssertTrue(RenderGapDetector.isGlitch(missed),
                      "one whole render deadline missed is a starved audio path")
    }

    /// And sub-deadline jitter must stay out of the log — an instrument that cries wolf
    /// gets ignored, which is how this repo lost 14 hours to a masked CI gate.
    func testSubDeadlineJitterIsNotAGlitch() {
        XCTAssertFalse(RenderGapDetector.isGlitch(report(elapsed: tapPeriod + quantum * 0.5)),
                       "half a render deadline late is jitter, not a missed deadline")
    }

    /// A paused graph is NOT a starved one. An interruption (Siri, a call) or a node
    /// attach restarts the engine, and the first interval afterwards spans the whole
    /// pause. Counting that as starvation would put `worst 1400×` in the founder's log
    /// and send the next cycle hunting a stall that never happened.
    func testAPauseSizedGapIsClassifiedAsDiscontinuity_notStarvation() {
        let paused = report(elapsed: tapPeriod + quantum * 40)
        XCTAssertTrue(RenderGapDetector.isDiscontinuity(paused))
        XCTAssertFalse(RenderGapDetector.isGlitch(paused),
                       "must not be counted twice, and must never reach worstLateInQuanta")

        let stall = report(elapsed: tapPeriod + quantum * 4)
        XCTAssertFalse(RenderGapDetector.isDiscontinuity(stall),
                       "a few deadlines late is a real stall, not a pause")
        XCTAssertTrue(RenderGapDetector.isGlitch(stall))
    }

    // MARK: - The verdict (the one branch able to INVERT the instrument)

    private func verdict(elapsed: Double, sampleGap: Int64?, previousFrames: Int? = nil)
        -> RenderGapDetector.Verdict {
        RenderGapDetector.classify(elapsedSeconds: elapsed,
                                   previousFrames: previousFrames ?? tapFrames,
                                   sampleGap: sampleGap,
                                   sampleRate: rate,
                                   renderQuantumFrames: quantumFrames)
    }

    /// THE REGRESSION TEST for the mistake that shipped for one commit: ANY sample-position
    /// drift was filed as "pause/restart, ignored". A drift of one render quantum is not a
    /// pause — it is audio that should have been rendered and was not, i.e. exactly the
    /// crackle. Treating it as a pause would have printed a confident "no starvation" over
    /// the top of the defect and ENDED the search.
    func testAForwardFramePositionSkipIsStarvation_notAPause() {
        // On time by the clock, but 512 frames of audio never happened. The lateness
        // field must stay ZERO: it is printed as a millisecond-convertible claim about the
        // clock, and the clock was fine. An earlier version returned max() in that field
        // and so reported wall-clock lateness that never happened.
        XCTAssertEqual(verdict(elapsed: tapPeriod, sampleGap: Int64(tapFrames + quantumFrames)),
                       .glitch(lateInQuanta: 0, driftInQuanta: 1))
    }

    /// Backwards, or beyond the pause ceiling, IS a restart — that half must survive.
    func testABackwardsOrHugeFramePositionJumpIsAPause() {
        XCTAssertEqual(verdict(elapsed: tapPeriod, sampleGap: 0), .discontinuity,
                       "the stream restarted from an earlier position")
        XCTAssertEqual(verdict(elapsed: tapPeriod,
                               sampleGap: Int64(tapFrames + quantumFrames * 40)), .discontinuity)
    }

    /// The interval covers the PREVIOUS buffer's audio, so that is what it is measured
    /// against. Comparing it to the current buffer's length made every change in delivered
    /// size look like a break — and alternating sizes would have pinned the glitch count at
    /// zero forever while the log still read "healthy".
    func testAChangeInDeliveredBufferSizeIsNotABreak() {
        // Previous delivery was 512 frames; this interval is exactly 512 frames long and
        // the position advanced by exactly 512. Nothing is wrong.
        XCTAssertEqual(verdict(elapsed: Double(quantumFrames) / rate,
                               sampleGap: Int64(quantumFrames),
                               previousFrames: quantumFrames), .onTime)
    }

    /// An unusable frame position must make that channel ABSTAIN, not vote. Otherwise a
    /// timestamp without sample time silently classifies every interval as a pause and the
    /// instrument reports zero glitches forever while looking healthy.
    func testAnAbsentFramePositionAbstains() {
        XCTAssertEqual(verdict(elapsed: tapPeriod, sampleGap: nil), .onTime)
        // No exact enum compare here: `(tapPeriod + quantum) - tapPeriod` is not bit-exact
        // (3·q needs 55 significand bits), so the payload lands 1 ulp either side of 1.
        guard case .glitch(let late, let drift) = verdict(elapsed: tapPeriod + quantum,
                                                          sampleGap: nil) else {
            return XCTFail("the wall-clock channel must still decide on its own")
        }
        XCTAssertEqual(late, 1, accuracy: 1e-9)
        XCTAssertEqual(drift, 0, "no frame evidence is reported as no drift, not as drift")
    }

    /// THE OTHER HALF of the same question, and the reason the verdict carries two
    /// numbers instead of one. A graph that is PAUSED but not stopped leaves the render
    /// position exactly where it was — the frame channel positively says "nothing was
    /// skipped" — while the clock says a tenth of a second went by. That is a different
    /// fault from a dropped render cycle, with the same symptom, and this instrument
    /// cannot tell them apart from inside. So it reports both and lets the first device
    /// log settle it, rather than picking one and calling it starvation.
    func testLatenessWithZeroFrameDriftIsReportedAsSuch() {
        guard case .glitch(let late, let drift) = verdict(elapsed: tapPeriod + quantum * 10,
                                                          sampleGap: Int64(tapFrames)) else {
            return XCTFail("ten quanta of wall clock is not on time")
        }
        XCTAssertEqual(late, 10, accuracy: 1e-9)
        XCTAssertEqual(drift, 0, "the render position did not move — say so, do not hide it")
    }

    /// An unmeasurable interval claims nothing in either direction.
    func testAnUnmeasurableIntervalIsNeverAVerdict() {
        XCTAssertEqual(verdict(elapsed: .nan, sampleGap: nil), .onTime)
        XCTAssertEqual(verdict(elapsed: tapPeriod, sampleGap: nil, previousFrames: 0), .onTime)
    }

    // MARK: - Boundaries (a NaN here would poison every later max())

    func testNonFiniteOrImpossibleInputsYieldAnEmptyReport_notNaN() {
        let cases: [(Double, Int, Double, Int)] = [
            (.nan, 1024, 48_000, 512), (.infinity, 1024, 48_000, 512),
            (0.01, 0, 48_000, 512), (0.01, -1, 48_000, 512),
            (0.01, 1024, 0, 512), (0.01, 1024, -48_000, 512), (0.01, 1024, .nan, 512),
            (0.01, 1024, 48_000, 0), (0.01, 1024, 48_000, -512)
        ]
        for (elapsed, f, sr, q) in cases {
            let r = RenderGapDetector.compare(elapsedSeconds: elapsed, frames: f,
                                              sampleRate: sr, renderQuantumFrames: q)
            XCTAssertEqual(r.lateBySeconds, 0, "elapsed \(elapsed) frames \(f) rate \(sr) quantum \(q)")
            XCTAssertEqual(r.expectedPeriodSeconds, 0)
            XCTAssertEqual(r.quantumSeconds, 0)
            XCTAssertEqual(r.lateInQuanta, 0, "must not divide by a zero quantum")
            XCTAssertFalse(RenderGapDetector.isGlitch(r),
                           "an unmeasurable interval is never evidence of a glitch")
            XCTAssertFalse(RenderGapDetector.isDiscontinuity(r))
        }
    }

    // MARK: - What the founder's log file actually says

    /// A clean tally must NOT read as "the crackle is gone". This detector only sees a
    /// starved audio path; a signal-path click leaves it at zero. The line has to say so,
    /// or the next report will be read as an all-clear it cannot support.
    ///
    /// This branch DOES ship: `AudioEngine` emits the first window unconditionally as the
    /// instrument's proof-of-life (an absent line would otherwise be indistinguishable
    /// from a dead instrument), and stays silent on clean windows after that.
    func testACleanLineDoesNotClaimTheCrackleIsGone() {
        let line = RenderGapDetector.Tally().diagnosticLine(overSeconds: 60,
                                                            quantumMilliseconds: 10.67)
        XCTAssertTrue(RenderGapDetector.Tally().isClean)
        XCTAssertTrue(line.contains("does not rule out"),
                      "a zero here narrows the search; it does not end it — \(line)")
        XCTAssertTrue(line.contains("10.67"),
                      "without the quantum in ms, a later multiplier cannot be converted "
                      + "back to milliseconds — \(line)")
    }

    func testADirtyLineCarriesTheCountTheWorstCaseAndTheUnit() {
        let line = RenderGapDetector.Tally(glitchCount: 7, worstLateInQuanta: 4.25,
                                           worstDriftInQuanta: 2.0, measuredIntervals: 5_600)
            .diagnosticLine(overSeconds: 60, quantumMilliseconds: 10.67)
        XCTAssertTrue(line.contains("7 late"),
                      "the count must come from the count, not from the 7 in 10.67 — \(line)")
        XCTAssertTrue(line.contains("4.2") || line.contains("4.3"), line)
        XCTAssertTrue(line.contains("10.67"), line)
        XCTAssertTrue(line.contains("frame drift 2.0"),
                      "the second channel must reach the log, not just the verdict — \(line)")
        XCTAssertTrue(line.contains("5600 intervals seen"),
                      "a window is only worth what it actually measured — \(line)")
        XCTAssertFalse(RenderGapDetector.Tally(glitchCount: 1).isClean)
    }

    /// Discarded pause gaps are reported, never hidden: a window that was mostly a
    /// stopped graph must not read like a window of clean playback.
    func testDiscardedPauseGapsAreVisibleInBothLines() {
        let clean = RenderGapDetector.Tally(discontinuityCount: 3)
            .diagnosticLine(overSeconds: 60, quantumMilliseconds: 10.67)
        XCTAssertTrue(clean.contains("3 pause/restart gaps ignored"), clean)

        let dirty = RenderGapDetector.Tally(glitchCount: 2, worstLateInQuanta: 1.5,
                                            discontinuityCount: 3)
            .diagnosticLine(overSeconds: 60, quantumMilliseconds: 10.67)
        XCTAssertTrue(dirty.contains("3 pause/restart gaps ignored"), dirty)

        XCTAssertFalse(RenderGapDetector.Tally().diagnosticLine(overSeconds: 60,
                                                                quantumMilliseconds: 10.67)
            .contains("ignored"), "no pause tail when there were none")
    }
}
