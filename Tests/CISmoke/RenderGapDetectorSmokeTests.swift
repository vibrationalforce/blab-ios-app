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
        let line = RenderGapDetector.Tally(glitchCount: 7, worstLateInQuanta: 4.25)
            .diagnosticLine(overSeconds: 60, quantumMilliseconds: 10.67)
        XCTAssertTrue(line.contains("7"), line)
        XCTAssertTrue(line.contains("4.2") || line.contains("4.3"), line)
        XCTAssertTrue(line.contains("10.67"), line)
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
            .contains("ignored"), "no tail when there were none")
    }
}
