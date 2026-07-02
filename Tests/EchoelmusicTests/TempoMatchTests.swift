import XCTest
@testable import Echoelmusic

/// Pure tempo-matching math for "Vorhören im Mastertempo" (see TempoMatch.swift).
final class TempoMatchTests: XCTestCase {

    func testNativeBPM_oneBarAtTwoSeconds_is120() {
        // 1 bar of 4/4 = 4 beats; 4 beats in 2 s → 120 BPM.
        let bpm = TempoMatch.nativeBPM(durationSeconds: 2.0, bars: 1)
        XCTAssertNotNil(bpm)
        XCTAssertEqual(bpm!, 120.0, accuracy: 0.0001)
    }

    func testNativeBPM_fourBarsAtFourSeconds_is240() {
        // 4 bars = 16 beats in 4 s → 240 BPM.
        let bpm = TempoMatch.nativeBPM(durationSeconds: 4.0, bars: 4)
        XCTAssertEqual(bpm!, 240.0, accuracy: 0.0001)
    }

    func testNativeBPM_guardsNonPositive() {
        XCTAssertNil(TempoMatch.nativeBPM(durationSeconds: 0, bars: 1))
        XCTAssertNil(TempoMatch.nativeBPM(durationSeconds: 2, bars: 0))
        XCTAssertNil(TempoMatch.nativeBPM(durationSeconds: 2, bars: 1, beatsPerBar: 0))
        XCTAssertNil(TempoMatch.nativeBPM(durationSeconds: -1, bars: 1))
    }

    func testStretchRate_matchesRatio() {
        // native 100, master 120 → 1.2×.
        XCTAssertEqual(TempoMatch.stretchRate(nativeBPM: 100, masterBPM: 120), 1.2, accuracy: 0.0001)
        // native 120, master 60 → 0.5×.
        XCTAssertEqual(TempoMatch.stretchRate(nativeBPM: 120, masterBPM: 60), 0.5, accuracy: 0.0001)
    }

    func testStretchRate_clampedToMusicalRange() {
        // native 20, master 200 → 10× raw, clamped to 4.0.
        XCTAssertEqual(TempoMatch.stretchRate(nativeBPM: 20, masterBPM: 200), 4.0, accuracy: 0.0001)
        // native 400, master 40 → 0.1× raw, clamped to 0.25.
        XCTAssertEqual(TempoMatch.stretchRate(nativeBPM: 400, masterBPM: 40), 0.25, accuracy: 0.0001)
    }

    func testStretchRate_nonPositiveIsNeutral() {
        XCTAssertEqual(TempoMatch.stretchRate(nativeBPM: 0, masterBPM: 120), 1.0, accuracy: 0.0001)
        XCTAssertEqual(TempoMatch.stretchRate(nativeBPM: 120, masterBPM: 0), 1.0, accuracy: 0.0001)
    }

    func testStretchRate_fromDuration_oneShotNotStretched() {
        // bars <= 0 → a one-shot → rate 1.0 (never time-stretched).
        XCTAssertEqual(TempoMatch.stretchRate(durationSeconds: 0.3, bars: 0, masterBPM: 128),
                       1.0, accuracy: 0.0001)
    }

    func testStretchRate_fromDuration_fitsLoop() {
        // 2 s, 1 bar → native 120; master 120 → 1.0×.
        XCTAssertEqual(TempoMatch.stretchRate(durationSeconds: 2.0, bars: 1, masterBPM: 120),
                       1.0, accuracy: 0.0001)
        // 2 s, 1 bar → native 120; master 140 → 140/120.
        XCTAssertEqual(TempoMatch.stretchRate(durationSeconds: 2.0, bars: 1, masterBPM: 140),
                       140.0 / 120.0, accuracy: 0.0001)
    }

    func testGuessBars_picksClosestFit() {
        // A ~2 s clip at master 120: 1 bar → native 120 (perfect). Should pick 1.
        XCTAssertEqual(TempoMatch.guessBars(durationSeconds: 2.0, masterBPM: 120), 1)
        // A ~4 s clip at master 120: 2 bars → native 120 (perfect). Should pick 2.
        XCTAssertEqual(TempoMatch.guessBars(durationSeconds: 4.0, masterBPM: 120), 2)
        // An 8 s clip at 120: 4 bars → native 120. Should pick 4.
        XCTAssertEqual(TempoMatch.guessBars(durationSeconds: 8.0, masterBPM: 120), 4)
    }

    func testGuessBars_guardsNonPositive() {
        XCTAssertNil(TempoMatch.guessBars(durationSeconds: 0, masterBPM: 120))
        XCTAssertNil(TempoMatch.guessBars(durationSeconds: 2, masterBPM: 0))
    }
}
