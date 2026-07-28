// LoopRetroCaptureFitTests.swift
// Echoel — the two loop-recording directions the founder asked for are NOT symmetric,
// and this pins the asymmetry so no UI can promise the wrong one.
//
//   "ab dem ersten Takt" (planned) → LoopExporter.exportWav writes LIVE to a file via
//     RetroCapture.startRecording(preRoll: 0). No history involved, so no length limit.
//   "rückwirkend für die letzten" (retroactive) → exportRecentLoop reads the always-on
//     30 s ring. It can only ever hand back what the ring still holds.
//
// The picker offers one bar count to both paths. Without this arithmetic the retroactive
// button is a lying control: at 120 BPM a bar is 2 s, so 16 bars (32 s) has already
// fallen out of the ring by the time you tap.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

final class LoopRetroCaptureFitTests: XCTestCase {

    // MARK: - The set the founder named

    func testTheBarSet_coversEveryLengthTheFounderAskedFor() {
        // Founder 2026-07-28: "Loop Recording von 2,4,8,16,32,64 Takten". 1 predates the
        // ask and stays — it is the audition length.
        XCTAssertEqual(LoopBarLength.allCases.map(\.rawValue), [1, 2, 4, 8, 16, 32, 64])
        XCTAssertEqual(LoopBarLength.sixtyFour.label, "64 bars")
        XCTAssertEqual(LoopBarLength.sixtyFour.shortLabel, "64")
    }

    func testTheRawValuesAreStable() {
        // @AppStorage persists the RAW Int. A renumbering would silently reinterpret a
        // saved preference as a different length, so the raw values are a contract.
        XCTAssertEqual(LoopBarLength.sixtyFour.rawValue, 64)
        XCTAssertEqual(LoopBarLength(rawValue: 64), .sixtyFour)
        XCTAssertNil(LoopBarLength(rawValue: 48), "an unknown length must fail to decode, not round")
    }

    // MARK: - What the ring can actually deliver

    func testKeepLast_fitsShrinkAsTheTempoSlows() {
        // A bar is 4 beats: barSeconds = 240 / bpm.
        // 120 BPM → 2 s/bar: 8 bars = 16 s fits, 16 bars = 32 s does not.
        XCTAssertTrue(LoopExporter.canKeepLast(bars: 8, bpm: 120))
        XCTAssertFalse(LoopExporter.canKeepLast(bars: 16, bpm: 120))
        // 60 BPM → 4 s/bar: the same ring now holds only half as many bars.
        XCTAssertTrue(LoopExporter.canKeepLast(bars: 4, bpm: 60))
        XCTAssertFalse(LoopExporter.canKeepLast(bars: 8, bpm: 60))
        // 240 BPM → 1 s/bar.
        XCTAssertTrue(LoopExporter.canKeepLast(bars: 16, bpm: 240))
        XCTAssertFalse(LoopExporter.canKeepLast(bars: 32, bpm: 240))
    }

    func testSixtyFourBars_canNeverBeKeptRetroactively_atAnyMusicalTempo() {
        // Transport clamps BPM to 30…300. Even at the fastest, 64 bars is
        // 64 × 240 / 300 = 51.2 s — well past the ring. So the retroactive door must be
        // shut for 64 at EVERY tempo, while the planned door stays open. This is the
        // asymmetry the UI has to show; it is not a bug to be tuned away.
        for bpm in [30.0, 120.0, 300.0] {
            XCTAssertFalse(LoopExporter.canKeepLast(bars: 64, bpm: bpm),
                           "64 bars must never claim to fit the ring at \(bpm) BPM")
        }
        // 32 bars, by contrast, DOES fit at the top of the range (25.6 s) — so the answer
        // genuinely depends on tempo and cannot be baked into the enum.
        XCTAssertTrue(LoopExporter.canKeepLast(bars: 32, bpm: 300))
        XCTAssertFalse(LoopExporter.canKeepLast(bars: 32, bpm: 120))
    }

    func testTheRefusal_namesALengthThePickerActuallyOffers() {
        // THE DEFECT THIS PINS: the first draft told the user the raw ring capacity —
        // "keep up to 14" at 120 BPM — and 14 is not a LoopBarLength case. A refusal that
        // sends you looking for a segment that does not exist is still a lying control.
        XCTAssertEqual(LoopExporter.longestKeepable(bpm: 120)?.rawValue, 8)   // 14 whole bars fit → 8 offered
        XCTAssertEqual(LoopExporter.longestKeepable(bpm: 60)?.rawValue, 4)    // 7 fit → 4 offered
        XCTAssertEqual(LoopExporter.longestKeepable(bpm: 300)?.rawValue, 32)  // 36 fit → 32 offered
        XCTAssertEqual(LoopExporter.longestKeepable(bpm: 30)?.rawValue, 2)    // 3 fit → 2 offered

        // Whatever it names must itself pass the gate — otherwise the advice is unfollowable.
        for bpm in [30.0, 60.0, 120.0, 300.0] {
            guard let best = LoopExporter.longestKeepable(bpm: bpm) else {
                return XCTFail("a legal tempo must always have some keepable length")
            }
            XCTAssertTrue(LoopExporter.canKeepLast(bars: best.rawValue, bpm: bpm))
        }

        // Unusable tempo → nil, so the UI says "unavailable" rather than naming "0 bars".
        XCTAssertNil(LoopExporter.longestKeepable(bpm: .nan))
        XCTAssertNil(LoopExporter.longestKeepable(bpm: 0))
    }

    func testTheBoundary_stepsCleanlyEitherSideOfTheRing() {
        // Choose the tempo at which 8 bars is exactly the ring length, then step either
        // side. Asserting ON the boundary would be a float-equality coin toss; asserting
        // that a hair longer fails and a hair shorter fits is what actually matters.
        let bars = 8.0
        let exactBPM = bars * 240.0 / LoopExporter.retroRingSeconds
        XCTAssertTrue(LoopExporter.canKeepLast(bars: 8, bpm: exactBPM * 1.001),
                      "slightly faster = slightly shorter loop = fits")
        XCTAssertFalse(LoopExporter.canKeepLast(bars: 8, bpm: exactBPM * 0.999),
                       "slightly slower = slightly longer loop = does not fit")
    }

    func testNonsenseTempoIsRejected_ratherThanDividedBy() {
        // The tempo reaching this comes from a bio-modulated transport, so 0 / NaN / inf
        // are edge cases at a real boundary, not impossibilities.
        XCTAssertFalse(LoopExporter.canKeepLast(bars: 4, bpm: 0))
        XCTAssertFalse(LoopExporter.canKeepLast(bars: 4, bpm: -120))
        XCTAssertFalse(LoopExporter.canKeepLast(bars: 4, bpm: .nan))
        XCTAssertFalse(LoopExporter.canKeepLast(bars: 4, bpm: .infinity))
    }

    func testZeroOrNegativeBars_areTreatedAsOne_notAsFree() {
        // `max(1, bars)` mirrors the exporter, so a nonsense bar count can never report
        // "fits" by collapsing the loop to zero seconds.
        XCTAssertTrue(LoopExporter.canKeepLast(bars: 0, bpm: 120))
        XCTAssertTrue(LoopExporter.canKeepLast(bars: -4, bpm: 120))
        XCTAssertFalse(LoopExporter.canKeepLast(bars: 0, bpm: 0.5),
                       "one bar at 0.5 BPM is 480 s — still must not fit")
    }

    // MARK: - The two paths must not be conflated

    func testEveryLengthUpToThirtyTwo_isPlannable_evenWhenNotKeepable() {
        // The planned path records live to a file and has no ring limit. This test exists
        // to stop a future "fix" that clamps the PICKER to what the ring can hold — that
        // would remove the founder's 64-bar ask from the path that can actually do it.
        for len in LoopBarLength.allCases {
            let seconds = StudioCalculator(bpm: 120).loopSeconds(bars: len.rawValue)
            XCTAssertGreaterThan(seconds, 0, "\(len.label) must be a plannable length")
        }
        XCTAssertEqual(StudioCalculator(bpm: 120).loopSeconds(bars: 64), 128, accuracy: 1e-9)
    }
}
#endif
