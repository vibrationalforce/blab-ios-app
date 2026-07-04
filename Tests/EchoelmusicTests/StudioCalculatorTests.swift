// StudioCalculatorTests.swift
// Echoel — verifies the production math against a known reference session
// (75.00 BPM · 44100 Hz · 4/4), matching a studio calculator to the millisecond.

import XCTest
@testable import Echoelmusic

final class StudioCalculatorTests: XCTestCase {

    private let acc = 0.001

    func testQuarterNoteAt75BPM() {
        let c = StudioCalculator(bpm: 75.00, sampleRate: 44_100, beatsPerBar: 4)
        XCTAssertEqual(c.milliseconds(.quarter), 800, accuracy: acc, "1/4 at 75 BPM = 800 ms")
        XCTAssertEqual(c.milliseconds(.quarter, .dotted), 1200, accuracy: acc, "dotted 1/4 = 1200 ms")
        XCTAssertEqual(c.milliseconds(.quarter, .triplet), 533.333, accuracy: 0.01, "triplet 1/4 ≈ 533 ms")
    }

    func testDivisionsAt75BPM() {
        let c = StudioCalculator(bpm: 75.00)
        XCTAssertEqual(c.milliseconds(.half), 1600, accuracy: acc)
        XCTAssertEqual(c.milliseconds(.eighth), 400, accuracy: acc)
        XCTAssertEqual(c.milliseconds(.sixteenth), 200, accuracy: acc)
        XCTAssertEqual(c.milliseconds(.thirtySecond), 100, accuracy: acc)
        XCTAssertEqual(c.milliseconds(.sixtyFourth), 50, accuracy: acc)
    }

    func testBarSecondsAndSamples() {
        let c = StudioCalculator(bpm: 75.00, sampleRate: 44_100, beatsPerBar: 4)
        XCTAssertEqual(c.barSeconds, 3.2, accuracy: acc, "1 bar at 75 BPM 4/4 = 3.2 s")
        XCTAssertEqual(c.loopSamples(bars: 1), 141_120, "3.2 s × 44100 = 141 120 samples")
    }

    func testHertzIsInverseOfSeconds() {
        let c = StudioCalculator(bpm: 120.00)
        // 1/4 at 120 BPM = 0.5 s → 2 Hz.
        XCTAssertEqual(c.hertz(.quarter), 2.0, accuracy: acc)
        XCTAssertEqual(c.seconds(.quarter), 0.5, accuracy: acc)
    }

    func testLoopLengthsScaleWithBars() {
        let c = StudioCalculator(bpm: 120.00, sampleRate: 48_000, beatsPerBar: 4)
        // 120 BPM 4/4 → 2 s per bar.
        XCTAssertEqual(c.loopSeconds(bars: 4), 8.0, accuracy: acc)
        XCTAssertEqual(c.loopSeconds(bars: 8), 16.0, accuracy: acc)
        for bars in [2, 4, 8, 16, 32] {
            XCTAssertEqual(c.loopSamples(bars: bars), bars * 2 * 48_000)
        }
    }

    func testZeroTempoIsSafe() {
        let c = StudioCalculator(bpm: 0)
        XCTAssertEqual(c.quarterNoteSeconds, 0)
        XCTAssertEqual(c.hertz(.quarter), 0)
        XCTAssertEqual(c.milliseconds(.quarter), 0)
    }

    func testTwoDecimalTempoPrecision() {
        let c = StudioCalculator(bpm: 128.37)
        // 60 / 128.37 = 0.46740… s per quarter.
        XCTAssertEqual(c.seconds(.quarter), 60.0 / 128.37, accuracy: 1e-9)
    }

    // MARK: - Genre tempo fold (audit B4 — body tempo INTO the genre window)

    func testGenreTempoPassesThroughWhenInRange() {
        XCTAssertEqual(StudioCalculator.genreTempo(120, into: 110...155), 120)
        XCTAssertEqual(StudioCalculator.genreTempo(66, into: 50...100), 66)
    }

    func testGenreTempoFoldsBodyPulseUpIntoTrap() {
        // Resting pulse 66 → double-time 132 lands inside Trap's 130–150.
        XCTAssertEqual(StudioCalculator.genreTempo(66, into: 130...150), 132)
        XCTAssertEqual(StudioCalculator.genreTempo(72, into: 130...150), 144)
    }

    func testGenreTempoFoldsRunawayEstimateBackDown() {
        // The 2× rPPG artifact (196) folds down to 98, then clamps to the window edge.
        XCTAssertEqual(StudioCalculator.genreTempo(196, into: 115...125), 115)
        XCTAssertEqual(StudioCalculator.genreTempo(196, into: 110...155), 110)
    }

    func testGenreTempoClampsWhenNoOctaveLandsInside() {
        // 66 → 132 → 264: neither octave is inside Punk 160–210 → nearest edge.
        XCTAssertEqual(StudioCalculator.genreTempo(66, into: 160...210), 160)
        // 90 doubles cleanly into the window.
        XCTAssertEqual(StudioCalculator.genreTempo(90, into: 160...210), 180)
    }

    func testGenreTempoTerminatesOnNarrowWindows() {
        // Windows narrower than an octave (ratio < 2) must still terminate + clamp.
        for t in [1.0, 40, 65.4321, 100, 133, 500, 10_000] {
            let r = StudioCalculator.genreTempo(t, into: 140...150)
            XCTAssertTrue((140...150).contains(r), "t=\(t) → \(r) must land in 140–150")
        }
    }

    func testGenreTempoGuardsDegenerateInput() {
        XCTAssertEqual(StudioCalculator.genreTempo(0, into: 130...150), 130)
        XCTAssertEqual(StudioCalculator.genreTempo(-20, into: 130...150), 130)
        XCTAssertEqual(StudioCalculator.genreTempo(.infinity, into: 130...150), 130)
        XCTAssertEqual(StudioCalculator.genreTempo(.nan, into: 130...150), 130)
    }
}
