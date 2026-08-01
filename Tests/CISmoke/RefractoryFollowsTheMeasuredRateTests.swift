// RefractoryFollowsTheMeasuredRateTests.swift
// Echoel — the beat-refractory is a TIME, and it was being converted with a guessed rate.
// In the BLOCKING bundle.
//
// WHAT THIS GUARDS (#373). `CameraAnalyzer.detectPeaks` spaces accepted peaks by a minimum
// distance in SAMPLES, computed from `refractorySeconds(autoBPM:)`. It used to multiply that
// by `effectiveSampleRate` — the ASSUMED 15 Hz, corrected at most ONCE (the re-tune sets
// `filterRateAdapted = true` unconditionally and only fires if the first ~2 s deviate by
// >15 %). The device logs record real capture rates of 7.5–15 Hz, and a rate that settles
// AFTER that one-shot window is never picked up.
//
// A refractory in samples derived from a rate twice the real one is twice as long in real
// time: real beats land inside it and are dropped, and the reading halves. Below the assumed
// rate the mirror happens — the window shortens, the dicrotic notch is admitted, the count
// doubles. Both are octave errors, which is precisely what this refractory exists to prevent
// (`CameraAnalyzerOctaveTests` guards the correction that has to clean up afterwards).
//
// ⚠️ WHAT A GREEN HERE DOES NOT MEAN. These are assertions about one pure conversion. They
// cannot say a pulse was read correctly on a device — only that the refractory now scales
// with the rate it is handed, and that hostile input cannot make it degenerate. The device
// look (does a 7.5 Hz capture still lock at the right BPM?) is the actual verification and
// is open.

#if canImport(AVFoundation)
import Foundation
import XCTest
@testable import Echoelmusic

final class RefractoryFollowsTheMeasuredRateTests: XCTestCase {

    typealias A = CameraAnalyzer

    // MARK: - The defect: samples must follow the rate, seconds must not

    /// The core invariant. Whatever rate comes in, dividing the returned sample count by that
    /// rate has to give back the refractory in SECONDS — that is what "a refractory is a time"
    /// means, and it is exactly what a fixed 15 Hz multiplier broke.
    func testTheRefractoryIsTheSameDurationAtEveryPlausibleCaptureRate() {
        for bpm in [0.0, 50, 72, 120, 175] {
            let seconds = A.refractorySeconds(autoBPM: bpm)
            for rate in [7.5, 10.0, 12.0, 15.0, 24.0, 30.0, 60.0] {
                let samples = A.refractorySamples(autoBPM: bpm, sampleRate: rate)
                let realSeconds = Double(samples) / rate
                // Truncation is preserved (see the helper's doc), so the realised duration can
                // sit up to one sample period BELOW the nominal one — never above it.
                XCTAssertLessThanOrEqual(realSeconds, seconds + 1e-9, """
                    At \(rate) Hz the refractory realises \(realSeconds) s, LONGER than the \
                    \(seconds) s asked for. Too long drops real beats and halves the reading — \
                    the octave error this refractory exists to prevent.
                    """)
                XCTAssertGreaterThan(realSeconds, seconds - 1.0 / rate - 1e-9, """
                    At \(rate) Hz the refractory realises \(realSeconds) s, more than one sample \
                    period short of \(seconds) s. Too short admits the dicrotic notch and \
                    doubles the count.
                    """)
            }
        }
    }

    /// The concrete device case, spelled out rather than left to the loop above: the logs show
    /// captures at half the assumed rate. Under the old fixed multiplier the sample count was
    /// identical at both rates, which is the bug in one line.
    func testHalvingTheCaptureRateHalvesTheSampleCountRatherThanTheDuration() {
        let atFifteen = A.refractorySamples(autoBPM: 72, sampleRate: 15)
        let atSevenAndAHalf = A.refractorySamples(autoBPM: 72, sampleRate: 7.5)
        XCTAssertEqual(Double(atFifteen) / Double(atSevenAndAHalf), 2.0, accuracy: 0.35, """
            A 7.5 Hz capture no longer needs roughly half the samples of a 15 Hz one \
            (\(atFifteen) vs \(atSevenAndAHalf)). If the count stopped following the rate, the \
            conversion is back on a guessed constant.
            """)
        XCTAssertNotEqual(atFifteen, atSevenAndAHalf, """
            The sample count is IDENTICAL at 15 Hz and 7.5 Hz. That is the exact signature of \
            the pre-#373 code, which multiplied by a fixed `effectiveSampleRate` regardless of \
            what the camera was actually delivering.
            """)
    }

    /// Bit-identity where it must hold: on a device that really runs at the assumed rate,
    /// nothing about this change may move, or the device look for #373 is unreadable.
    func testAtTheAssumedRateTheResultIsTheOldNumber() {
        for bpm in [0.0, 39.0, 50, 72, 120, 175, 181.0] {
            let old = Int(15.0 * A.refractorySeconds(autoBPM: bpm))
            XCTAssertEqual(A.refractorySamples(autoBPM: bpm, sampleRate: 15), old, """
                At the assumed 15 Hz the refractory for autoBPM \(bpm) changed from \(old) \
                samples. This slice is a no-op on a device that runs at the assumed rate; any \
                difference here is an unintended behaviour change riding along.
                """)
        }
    }

    // MARK: - Hostile input, because the rate is now measurement-derived

    /// `Int(Double.nan)` TRAPS in Swift — a crash, not a wrong number. The rate now comes from
    /// a timestamp span, so this stopped being hypothetical the moment the call site changed.
    func testANonFiniteOrNonPositiveRateFallsBackInsteadOfTrapping() {
        for bad in [Double.nan, .infinity, -Double.infinity, 0, -30] {
            let samples = A.refractorySamples(autoBPM: 72, sampleRate: bad)
            XCTAssertEqual(samples, A.refractorySamples(autoBPM: 72, sampleRate: 15), """
                A sample rate of \(bad) did not fall back to the assumed rate. Either it \
                trapped on the Int conversion, or it produced a distance derived from garbage.
                """)
        }
    }

    /// A distance of zero is the silent failure: every local maximum is accepted, so the notch
    /// doubles the count and nothing crashes to point at it.
    func testTheDistanceIsNeverZeroOrNegative() {
        for rate in [0.0001, 0.5, 1.0, 7.5, 15.0, 1_000_000.0] {
            for bpm in [0.0, 40, 72, 180, 5_000.0] {
                let samples = A.refractorySamples(autoBPM: bpm, sampleRate: rate)
                XCTAssertGreaterThanOrEqual(samples, 1, """
                    rate \(rate) Hz / autoBPM \(bpm) produced a refractory of \(samples) \
                    samples. Below 1 the peak scan accepts adjacent samples as separate beats.
                    """)
            }
        }
    }

    /// The upper clamp. A corrupt timestamp span could report an absurd rate; without a ceiling
    /// the distance would exceed the analysis window and no peak would ever be accepted — a
    /// silent zero-BPM run, which the device logs already show is hard to tell from "no finger".
    func testAnAbsurdRateCannotSwallowTheWholeWindow() {
        // The scan looks at roughly 10 s of samples; at the ceiling (240 Hz) that is ~2400.
        let samples = A.refractorySamples(autoBPM: 72, sampleRate: 100_000)
        XCTAssertLessThanOrEqual(samples, 240, """
            An absurd measured rate produced a refractory of \(samples) samples. Longer than the \
            window means zero accepted peaks and a permanent bpm=0, with no error anywhere.
            """)
    }
}
#endif
