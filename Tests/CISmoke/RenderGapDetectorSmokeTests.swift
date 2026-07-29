// RenderGapDetectorSmokeTests.swift
// Echoel — the rule that decides whether "es knistert" gets a number or another guess.
//
// WHY IT IS IN CISmoke, since this bundle must not become a dumping ground: it is the
// BLOCKING bundle (`project.yml`'s `EchoelmusicTests` target sources only this directory;
// everything under `Tests/EchoelmusicTests` runs in a workflow whose build step carries
// `continue-on-error` — #208). Two reasons this one earns a gate:
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

    // 512 frames at 48 kHz — the shipping buffer (`AudioConfiguration`), ≈ 10.67 ms.
    private let frames = 512
    private let rate: Double = 48_000
    private var period: Double { Double(frames) / rate }

    // MARK: - The measurement

    /// On-time and early intervals are not lateness. Early matters: Core Audio delivers
    /// taps in bursts, so a short interval is normal and must never register as negative
    /// lateness that a later `max()` would then treat as the best case.
    func testAnOnTimeOrEarlyIntervalIsNotLate() {
        for elapsed in [period, period * 0.5, 0.0] {
            let r = RenderGapDetector.compare(elapsedSeconds: elapsed, frames: frames, sampleRate: rate)
            XCTAssertEqual(r.lateBySeconds, 0, accuracy: 1e-12, "elapsed \(elapsed)")
            XCTAssertFalse(RenderGapDetector.isGlitch(r))
        }
    }

    /// Lateness is measured against the buffer period, and reported scale-free so the
    /// number means the same thing at any sample rate or buffer size.
    func testLatenessIsMeasuredInWholeBufferPeriods() {
        let r = RenderGapDetector.compare(elapsedSeconds: period * 3, frames: frames, sampleRate: rate)
        XCTAssertEqual(r.lateBySeconds, period * 2, accuracy: 1e-9)
        XCTAssertEqual(r.lateInBuffers, 2, accuracy: 1e-9,
                       "three periods elapsed = two periods late")
    }

    /// Same lateness in buffers must read the same at a different rate and buffer size —
    /// otherwise the threshold below means different things on different hardware, and a
    /// media-services reset can change the rate mid-session (#212).
    func testTheScaleFreeNumberIsIndependentOfRateAndBufferSize() {
        let a = RenderGapDetector.compare(elapsedSeconds: (512.0 / 48_000) * 2.5,
                                          frames: 512, sampleRate: 48_000)
        let b = RenderGapDetector.compare(elapsedSeconds: (256.0 / 44_100) * 2.5,
                                          frames: 256, sampleRate: 44_100)
        XCTAssertEqual(a.lateInBuffers, b.lateInBuffers, accuracy: 1e-9)
    }

    // MARK: - The threshold

    /// THE RULE THE DIAGNOSTICS FILE DEPENDS ON. Ordinary scheduler jitter must not be
    /// logged — an instrument that cries wolf gets ignored, which is how this repo lost
    /// 14 hours to a masked CI gate. One WHOLE buffer period late is the bar.
    func testOrdinaryJitterIsNotAGlitch_butAFullPeriodLateIs() {
        let jitter = RenderGapDetector.compare(elapsedSeconds: period * 1.9,
                                               frames: frames, sampleRate: rate)
        XCTAssertFalse(RenderGapDetector.isGlitch(jitter),
                       "0.9 of a period late is jitter, not a missed deadline")

        let missed = RenderGapDetector.compare(elapsedSeconds: period * 2.1,
                                               frames: frames, sampleRate: rate)
        XCTAssertTrue(RenderGapDetector.isGlitch(missed),
                      "more than one whole buffer period late is a starved audio path")
    }

    // MARK: - Boundaries (a NaN here would poison every later max())

    func testNonFiniteOrImpossibleInputsYieldAnEmptyReport_notNaN() {
        let cases: [(Double, Int, Double)] = [
            (.nan, 512, 48_000), (.infinity, 512, 48_000),
            (0.01, 0, 48_000), (0.01, -1, 48_000),
            (0.01, 512, 0), (0.01, 512, -48_000), (0.01, 512, .nan)
        ]
        for (elapsed, f, sr) in cases {
            let r = RenderGapDetector.compare(elapsedSeconds: elapsed, frames: f, sampleRate: sr)
            XCTAssertEqual(r.lateBySeconds, 0, "elapsed \(elapsed) frames \(f) rate \(sr)")
            XCTAssertEqual(r.expectedPeriodSeconds, 0)
            XCTAssertEqual(r.lateInBuffers, 0, "must not divide by a zero period")
            XCTAssertFalse(RenderGapDetector.isGlitch(r),
                           "an unmeasurable interval is never evidence of a glitch")
        }
    }

    // MARK: - What the founder's log file actually says

    /// A clean tally must NOT read as "the crackle is gone". This detector only sees
    /// thread starvation; a signal-path click leaves it at zero. The line has to say so,
    /// or the next report will be read as an all-clear it cannot support.
    ///
    /// Honesty about scope: `AudioEngine.pollAudioTiming` writes NOTHING for a clean
    /// window — a line every 60 s would bury the dirty ones. So this branch is not on the
    /// per-window path today; it is pinned because the caveat has to already be in the
    /// string on the day something DOES ask the tally to report itself.
    func testACleanLineDoesNotClaimTheCrackleIsGone() {
        let line = RenderGapDetector.Tally().diagnosticLine(overSeconds: 60)
        XCTAssertTrue(RenderGapDetector.Tally().isClean)
        XCTAssertTrue(line.contains("does not rule out"),
                      "a zero here narrows the search; it does not end it — \(line)")
    }

    func testADirtyLineCarriesBothTheCountAndTheWorstCase() {
        let line = RenderGapDetector.Tally(glitchCount: 7, worstLateInBuffers: 4.25)
            .diagnosticLine(overSeconds: 60)
        XCTAssertTrue(line.contains("7"), line)
        XCTAssertTrue(line.contains("4.2") || line.contains("4.3"), line)
        XCTAssertFalse(RenderGapDetector.Tally(glitchCount: 1).isClean)
    }
}
