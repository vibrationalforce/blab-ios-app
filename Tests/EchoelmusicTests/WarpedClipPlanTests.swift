import XCTest
@testable import Echoelmusic

final class WarpedClipPlanTests: XCTestCase {

    private let sr = 48_000.0

    // MARK: rate == 1.0 short-circuit

    func testStretchRate_WarpOff_IsOne() {
        let region = AudioClipRegion(startSeconds: 0, endSeconds: 2,
                                     warpEnabled: false, nativeBPM: 100)
        let plan = WarpedClipPlan(region: region, startTick: 0,
                                  projectBPM: 140, engineSampleRate: sr)
        XCTAssertEqual(plan.stretchRate, 1.0)
        // No stretch → output length equals source length.
        XCTAssertEqual(plan.outputFrameCount, plan.sourceFrameCount)
    }

    func testStretchRate_NonPositiveBPM_IsOne() {
        let region = AudioClipRegion(startSeconds: 0, endSeconds: 2,
                                     warpEnabled: true, nativeBPM: 100)
        let plan = WarpedClipPlan(region: region, startTick: 0,
                                  projectBPM: 0, engineSampleRate: sr)
        XCTAssertEqual(plan.stretchRate, 1.0)
        XCTAssertEqual(plan.outputFrameCount, plan.sourceFrameCount)
    }

    func testStretchRate_UnknownNativeBPM_IsOne() {
        let region = AudioClipRegion(startSeconds: 0, endSeconds: 2,
                                     warpEnabled: true, nativeBPM: 0)
        let plan = WarpedClipPlan(region: region, startTick: 0,
                                  projectBPM: 120, engineSampleRate: sr)
        XCTAssertEqual(plan.stretchRate, 1.0)
    }

    // MARK: source frames

    func testSourceFrames_MatchTrimSeconds() {
        // trim 0.5s … 2.5s → 2.0s duration; start 0.5s.
        let region = AudioClipRegion(startSeconds: 0.5, endSeconds: 2.5)
        let plan = WarpedClipPlan(region: region, startTick: 0,
                                  projectBPM: 120, engineSampleRate: sr)
        XCTAssertEqual(plan.sourceStartFrame, Int((0.5 * sr).rounded()))
        XCTAssertEqual(plan.sourceFrameCount, Int((2.0 * sr).rounded()))
    }

    // MARK: output shrinks / grows with rate

    func testOutputFrameCount_ShrinksForRateAboveOne() {
        // project (200) faster than clip (100) → rate 2.0 → half the frames.
        let region = AudioClipRegion(startSeconds: 0, endSeconds: 2,
                                     warpEnabled: true, nativeBPM: 100)
        let plan = WarpedClipPlan(region: region, startTick: 0,
                                  projectBPM: 200, engineSampleRate: sr)
        XCTAssertEqual(plan.stretchRate, 2.0, accuracy: 1e-9)
        XCTAssertLessThan(plan.outputFrameCount, plan.sourceFrameCount)
        XCTAssertEqual(plan.outputFrameCount,
                       Int((Double(plan.sourceFrameCount) / 2.0).rounded()))
    }

    func testOutputFrameCount_GrowsForRateBelowOne() {
        // project (100) slower than clip (200) → rate 0.5 → double the frames.
        let region = AudioClipRegion(startSeconds: 0, endSeconds: 2,
                                     warpEnabled: true, nativeBPM: 200)
        let plan = WarpedClipPlan(region: region, startTick: 0,
                                  projectBPM: 100, engineSampleRate: sr)
        XCTAssertEqual(plan.stretchRate, 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan(plan.outputFrameCount, plan.sourceFrameCount)
    }

    // MARK: onset monotonic in startTick

    func testOnset_MonotonicInStartTick() {
        let region = AudioClipRegion(startSeconds: 0, endSeconds: 1)
        var lastOnset = -1
        for tick in stride(from: 0, through: 1920 * 4, by: 240) {
            let plan = WarpedClipPlan(region: region, startTick: tick,
                                      projectBPM: 120, engineSampleRate: sr)
            XCTAssertGreaterThanOrEqual(plan.onsetSampleOffset, lastOnset)
            lastOnset = plan.onsetSampleOffset
        }
    }

    func testOnset_ZeroTick_IsZero() {
        let region = AudioClipRegion(startSeconds: 0, endSeconds: 1)
        let plan = WarpedClipPlan(region: region, startTick: 0,
                                  projectBPM: 120, engineSampleRate: sr)
        XCTAssertEqual(plan.onsetSampleOffset, 0)
    }

    func testOnset_NegativeTick_ClampedToZero() {
        let region = AudioClipRegion(startSeconds: 0, endSeconds: 1)
        let plan = WarpedClipPlan(region: region, startTick: -500,
                                  projectBPM: 120, engineSampleRate: sr)
        XCTAssertEqual(plan.onsetSampleOffset, 0)
    }

    // MARK: 1-bar clip at matching tempo → integer-bar output

    func testOneBarClip_MatchingBPM_WarpsToIntegerBarLength() {
        // 1 bar 4/4 at 120 BPM = 2.0 s. At 48 kHz that is 96_000 frames — an exact
        // integer bar length. Warp on with nativeBPM == projectBPM ⇒ rate 1.0.
        let barSeconds = TimelineTime.seconds(fromTicks: TimelineTime.ticksPerBar, bpm: 120)
        let region = AudioClipRegion(startSeconds: 0, endSeconds: barSeconds,
                                     warpEnabled: true, nativeBPM: 120)
        let plan = WarpedClipPlan(region: region, startTick: 0,
                                  projectBPM: 120, engineSampleRate: sr)
        XCTAssertEqual(plan.stretchRate, 1.0)
        let expected = Int((barSeconds * sr).rounded())
        XCTAssertEqual(plan.outputFrameCount, expected)
        XCTAssertEqual(plan.outputFrameCount, 96_000)
    }

    // MARK: edge cases

    func testZeroSampleRate_YieldsZeroFrames() {
        let region = AudioClipRegion(startSeconds: 0, endSeconds: 2,
                                     warpEnabled: true, nativeBPM: 100)
        let plan = WarpedClipPlan(region: region, startTick: 1920,
                                  projectBPM: 120, engineSampleRate: 0)
        XCTAssertEqual(plan.sourceStartFrame, 0)
        XCTAssertEqual(plan.sourceFrameCount, 0)
        XCTAssertEqual(plan.outputFrameCount, 0)
        XCTAssertEqual(plan.onsetSampleOffset, 0)
        // Rate is still reported from the region.
        XCTAssertGreaterThan(plan.stretchRate, 0)
    }

    func testNegativeSampleRate_YieldsZeroFrames() {
        let region = AudioClipRegion(startSeconds: 0, endSeconds: 2)
        let plan = WarpedClipPlan(region: region, startTick: 0,
                                  projectBPM: 120, engineSampleRate: -44_100)
        XCTAssertEqual(plan.sourceFrameCount, 0)
        XCTAssertEqual(plan.outputFrameCount, 0)
    }

    func testAllFrameFieldsNonNegative() {
        let region = AudioClipRegion(startSeconds: 0.25, endSeconds: 0.75,
                                     warpEnabled: true, nativeBPM: 90)
        let plan = WarpedClipPlan(region: region, startTick: 3840,
                                  projectBPM: 128, engineSampleRate: sr)
        XCTAssertGreaterThanOrEqual(plan.sourceStartFrame, 0)
        XCTAssertGreaterThanOrEqual(plan.sourceFrameCount, 0)
        XCTAssertGreaterThanOrEqual(plan.outputFrameCount, 0)
        XCTAssertGreaterThanOrEqual(plan.onsetSampleOffset, 0)
    }
}
