// AudioRegionPlaybackTests.swift
// The pure media-time mapping for transport audio playback: file position + start
// frame + segment frame count. These pin the brain of the upcoming AudioLanePlayer
// so its AVFoundation executor can be a thin, device-verified shell.
// Reference: TimelineTime.seconds(fromTicks: 480, bpm: 120) == 0.5 s (a quarter @120).

import XCTest
@testable import Echoelmusic

final class AudioRegionPlaybackTests: XCTestCase {

    private let lane = UUID()
    private let clip = UUID()

    /// A one-bar (1920-tick) region starting at `start`, media trimmed in by `offset`.
    private func region(start: Int, length: Int = 1920, offset: Double = 0) -> TimelineRegion {
        TimelineRegion(laneID: lane, clipID: clip, startTick: start,
                       lengthTicks: length, contentOffsetSeconds: offset)
    }

    // MARK: - filePositionSeconds

    func testFilePosition_atRegionStart_isContentOffset() {
        let r = region(start: 480, offset: 2.0)
        XCTAssertEqual(AudioRegionPlayback.filePositionSeconds(for: r, atTick: 480, bpm: 120),
                       2.0, accuracy: 1e-9, "at the region start the file plays from its trim-in point")
    }

    func testFilePosition_midRegion_advancesByElapsed() {
        // Enter 480 ticks (0.5 s @120) into a region that starts at tick 0, trim-in 2.0.
        let r = region(start: 0, offset: 2.0)
        XCTAssertEqual(AudioRegionPlayback.filePositionSeconds(for: r, atTick: 480, bpm: 120),
                       2.5, accuracy: 1e-9, "mid-region the file position = offset + elapsed")
    }

    func testFilePosition_outsideRegion_isNil() {
        let r = region(start: 100, length: 800)              // [100, 900)
        XCTAssertNil(AudioRegionPlayback.filePositionSeconds(for: r, atTick: 99, bpm: 120))
        XCTAssertNil(AudioRegionPlayback.filePositionSeconds(for: r, atTick: 900, bpm: 120),
                     "endTick is exclusive")
        XCTAssertNotNil(AudioRegionPlayback.filePositionSeconds(for: r, atTick: 899, bpm: 120))
    }

    // MARK: - startFrame

    func testStartFrame_flooredToSampleRate() {
        let r = region(start: 0, offset: 2.0)
        // At tick 480 → 2.5 s → 2.5 * 48000 = 120000 frames.
        XCTAssertEqual(AudioRegionPlayback.startFrame(for: r, atTick: 480, bpm: 120, sampleRate: 48_000),
                       120_000)
    }

    func testStartFrame_outsideRegion_orBadRate_isNil() {
        let r = region(start: 0)
        XCTAssertNil(AudioRegionPlayback.startFrame(for: r, atTick: 5000, bpm: 120, sampleRate: 48_000))
        XCTAssertNil(AudioRegionPlayback.startFrame(for: r, atTick: 0, bpm: 120, sampleRate: 0))
    }

    /// Fractional-frame case: pins that startFrame FLOORS (not rounds). At 100 BPM /
    /// 44.1 kHz, tick 7 → 7/480·0.6 = 0.00875 s → ·44100 = 385.875 → floor 385
    /// (a round would give 386). 120 BPM/48 kHz above is tick-exact and can't tell them apart.
    func testStartFrame_usesFloor_notRound() {
        let r = region(start: 0)
        XCTAssertEqual(AudioRegionPlayback.startFrame(for: r, atTick: 7, bpm: 100, sampleRate: 44_100), 385)
    }

    // MARK: - frameCount

    func testFrameCount_fromStart_isWholeRegion() {
        // 1 bar = 1920 ticks = 4 beats @120 = 2.0 s → 96000 frames @48k.
        let r = region(start: 0)
        XCTAssertEqual(AudioRegionPlayback.frameCount(for: r, fromTick: 0, bpm: 120, sampleRate: 48_000),
                       96_000)
    }

    func testFrameCount_midRegion_isRemainder() {
        // Enter 480 ticks in → 1440 ticks left = 1.5 s → 72000 frames.
        let r = region(start: 0)
        XCTAssertEqual(AudioRegionPlayback.frameCount(for: r, fromTick: 480, bpm: 120, sampleRate: 48_000),
                       72_000)
    }

    func testFrameCount_atOrPastEnd_isZero() {
        let r = region(start: 0)                              // ends at 1920
        XCTAssertEqual(AudioRegionPlayback.frameCount(for: r, fromTick: 1920, bpm: 120, sampleRate: 48_000), 0)
        XCTAssertEqual(AudioRegionPlayback.frameCount(for: r, fromTick: 3000, bpm: 120, sampleRate: 48_000), 0)
    }

    /// Fractional-frame case: pins that frameCount ROUNDS (not floors). A 5-tick
    /// region @100 BPM / 44.1 kHz: 5/480·0.6 = 0.00625 s → ·44100 = 275.625 → round 276
    /// (a floor would give 275).
    func testFrameCount_usesRound_notFloor() {
        let r = region(start: 0, length: 5)
        XCTAssertEqual(AudioRegionPlayback.frameCount(for: r, fromTick: 0, bpm: 100, sampleRate: 44_100), 276)
    }

    func testFrameCount_beforeStart_measuresWholeRegion() {
        // Defensive: a tick before the region start measures the full region.
        let r = region(start: 960)                            // [960, 2880), 2.0 s long
        XCTAssertEqual(AudioRegionPlayback.frameCount(for: r, fromTick: 0, bpm: 120, sampleRate: 48_000),
                       96_000)
    }
}
