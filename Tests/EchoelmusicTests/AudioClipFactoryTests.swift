import XCTest
@testable import Echoelmusic

final class AudioClipFactoryTests: XCTestCase {

    // MARK: - clip()

    func testClip_setsAudioKindAndMediaRef() {
        let clip = AudioClipFactory.clip(name: "Vocal Take", mediaRef: "take01.wav")
        XCTAssertEqual(clip.kind, .audio)
        XCTAssertEqual(clip.name, "Vocal Take")
        XCTAssertEqual(clip.mediaRef, "take01.wav")
        XCTAssertNil(clip.drums)
        XCTAssertNil(clip.melody)
    }

    func testClip_withMediaRef_isNotEmpty() {
        let clip = AudioClipFactory.clip(name: "Loop", mediaRef: "loop.wav")
        XCTAssertFalse(clip.isEmpty)
    }

    func testClip_emptyMediaRef_isEmpty() {
        // An audio clip carries content via mediaRef — an empty ref means no content.
        let clip = AudioClipFactory.clip(name: "Empty", mediaRef: "")
        XCTAssertTrue(clip.isEmpty)
    }

    func testClip_honorsColorIndex() {
        let clip = AudioClipFactory.clip(name: "C", mediaRef: "c.wav", colorIndex: 3)
        XCTAssertEqual(clip.colorIndex, 3)
    }

    // MARK: - region()

    func testRegion_lengthMatchesBarsTimesTicksPerBar() {
        // 4 bars of 4/4 at 120 BPM = 8 s. nativeBPM 120 → 4 bars → 4 * 1920 ticks.
        let lane = UUID()
        let clip = UUID()
        let region = AudioClipFactory.region(forDurationSeconds: 8.0,
                                             bpm: 120,
                                             laneID: lane,
                                             clipID: clip,
                                             startTick: 0,
                                             nativeBPM: 120)
        XCTAssertEqual(region.lengthTicks, 4 * TimelineTime.ticksPerBar)
        XCTAssertEqual(region.laneID, lane)
        XCTAssertEqual(region.clipID, clip)
        XCTAssertEqual(region.startTick, 0)
    }

    func testRegion_oneBar() {
        // 2 s at 120 BPM = 1 bar (4 beats).
        let region = AudioClipFactory.region(forDurationSeconds: 2.0,
                                             bpm: 120,
                                             laneID: UUID(),
                                             clipID: UUID(),
                                             startTick: 480,
                                             nativeBPM: 120)
        XCTAssertEqual(region.lengthTicks, TimelineTime.ticksPerBar)
        XCTAssertEqual(region.startTick, 480)
    }

    func testRegion_clampsNegativeStartTick() {
        let region = AudioClipFactory.region(forDurationSeconds: 8.0,
                                             bpm: 120,
                                             laneID: UUID(),
                                             clipID: UUID(),
                                             startTick: -100,
                                             nativeBPM: 120)
        XCTAssertEqual(region.startTick, 0)
    }

    func testRegion_clampsNegativeContentOffset() {
        let region = AudioClipFactory.region(forDurationSeconds: 8.0,
                                             bpm: 120,
                                             laneID: UUID(),
                                             clipID: UUID(),
                                             startTick: 0,
                                             nativeBPM: 120,
                                             contentOffsetSeconds: -5)
        XCTAssertEqual(region.contentOffsetSeconds, 0)
    }

    func testRegion_zeroDuration_fallsBackToOneBar() {
        // Never a zero-length region — floors at one bar.
        let region = AudioClipFactory.region(forDurationSeconds: 0,
                                             bpm: 120,
                                             laneID: UUID(),
                                             clipID: UUID(),
                                             startTick: 0,
                                             nativeBPM: 120)
        XCTAssertEqual(region.lengthTicks, TimelineTime.ticksPerBar)
    }

    func testRegion_zeroNativeBPM_fallsBackToOneBar() {
        let region = AudioClipFactory.region(forDurationSeconds: 8.0,
                                             bpm: 120,
                                             laneID: UUID(),
                                             clipID: UUID(),
                                             startTick: 0,
                                             nativeBPM: 0)
        XCTAssertEqual(region.lengthTicks, TimelineTime.ticksPerBar)
    }

    func testRegion_deterministic() {
        let lane = UUID()
        let clip = UUID()
        let a = AudioClipFactory.region(forDurationSeconds: 8.0, bpm: 120,
                                        laneID: lane, clipID: clip,
                                        startTick: 240, nativeBPM: 120)
        let b = AudioClipFactory.region(forDurationSeconds: 8.0, bpm: 120,
                                        laneID: lane, clipID: clip,
                                        startTick: 240, nativeBPM: 120)
        XCTAssertEqual(a.lengthTicks, b.lengthTicks)
        XCTAssertEqual(a.startTick, b.startTick)
        XCTAssertEqual(a.laneID, b.laneID)
        XCTAssertEqual(a.clipID, b.clipID)
    }

    // MARK: - guessBars()

    func testGuessBars_pickAFourBarLoop() {
        // 8 s at 120 BPM is exactly 4 bars.
        XCTAssertEqual(AudioClipFactory.guessBars(forDurationSeconds: 8.0, bpm: 120), 4)
    }

    func testGuessBars_pickAOneBarLoop() {
        // 2 s at 120 BPM is exactly 1 bar.
        XCTAssertEqual(AudioClipFactory.guessBars(forDurationSeconds: 2.0, bpm: 120), 1)
    }

    func testGuessBars_pickATwoBarLoop() {
        // 4 s at 120 BPM is exactly 2 bars.
        XCTAssertEqual(AudioClipFactory.guessBars(forDurationSeconds: 4.0, bpm: 120), 2)
    }

    func testGuessBars_returnsPositiveInteger() {
        let bars = AudioClipFactory.guessBars(forDurationSeconds: 5.3, bpm: 128)
        XCTAssertGreaterThanOrEqual(bars, 1)
    }

    func testGuessBars_zeroDuration_fallsBackToOne() {
        XCTAssertEqual(AudioClipFactory.guessBars(forDurationSeconds: 0, bpm: 120), 1)
    }

    func testGuessBars_negativeBPM_fallsBackToOne() {
        XCTAssertEqual(AudioClipFactory.guessBars(forDurationSeconds: 8.0, bpm: -1), 1)
    }

    // MARK: - nativeBPM()

    func testNativeBPM_fourBarLoopAt120() {
        // 8 s / 4 bars = 120 BPM.
        XCTAssertEqual(AudioClipFactory.nativeBPM(forDurationSeconds: 8.0, bpm: 120),
                       120, accuracy: 0.001)
    }

    func testNativeBPM_nonPositiveInputs_returnZeroOrPassthrough() {
        // Zero duration → falls back to bpm (never negative).
        XCTAssertEqual(AudioClipFactory.nativeBPM(forDurationSeconds: 0, bpm: 120), 120,
                       accuracy: 0.001)
        // Zero bpm → 0, never negative (safe to divide guardedly downstream).
        XCTAssertEqual(AudioClipFactory.nativeBPM(forDurationSeconds: 8.0, bpm: 0), 0,
                       accuracy: 0.001)
    }

    func testNativeBPM_isPositiveForRealisticInput() {
        let bpm = AudioClipFactory.nativeBPM(forDurationSeconds: 3.7, bpm: 128)
        XCTAssertGreaterThan(bpm, 0)
    }
}
