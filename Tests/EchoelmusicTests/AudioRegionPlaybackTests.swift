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

    func testFilePosition_atRegionStart_isContentOffset() throws {
        let r = region(start: 480, offset: 2.0)
        let pos = try XCTUnwrap(AudioRegionPlayback.filePositionSeconds(for: r, atTick: 480, bpm: 120))
        XCTAssertEqual(pos, 2.0, accuracy: 1e-9, "at the region start the file plays from its trim-in point")
    }

    func testFilePosition_midRegion_advancesByElapsed() throws {
        // Enter 480 ticks (0.5 s @120) into a region that starts at tick 0, trim-in 2.0.
        let r = region(start: 0, offset: 2.0)
        let pos = try XCTUnwrap(AudioRegionPlayback.filePositionSeconds(for: r, atTick: 480, bpm: 120))
        XCTAssertEqual(pos, 2.5, accuracy: 1e-9, "mid-region the file position = offset + elapsed")
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

    // MARK: - auditionWindow (H13: region tap plays ITS window, never file-start)

    func testAuditionWindow_startsAtContentOffset_forRegionLength() {
        // A 1-bar region @120 (2.0 s) trimmed 1.5 s into its media.
        let r = region(start: 480, offset: 1.5)
        let w = AudioRegionPlayback.auditionWindow(for: r, bpm: 120, transportPlaying: false)
        XCTAssertEqual(w?.fromSeconds ?? -1, 1.5, accuracy: 1e-9,
                       "audition starts at the region's trim-in point, not file-start")
        XCTAssertEqual(w?.lengthSeconds ?? -1, 2.0, accuracy: 1e-9,
                       "audition lasts exactly the region's musical length")
    }

    func testAuditionWindow_whileTransportPlays_isNil() {
        // The lane sink already sounds this lane while playing — a second node would
        // double-sound; nil also keeps the sink's lazy attach-pause off running audio.
        let r = region(start: 0, offset: 1.0)
        XCTAssertNil(AudioRegionPlayback.auditionWindow(for: r, bpm: 120, transportPlaying: true))
    }

    func testAuditionWindow_badTempoOrEmptyRegion_isNil() {
        XCTAssertNil(AudioRegionPlayback.auditionWindow(for: region(start: 0), bpm: 0,
                                                        transportPlaying: false))
        XCTAssertNil(AudioRegionPlayback.auditionWindow(for: region(start: 0), bpm: -120,
                                                        transportPlaying: false))
        XCTAssertNil(AudioRegionPlayback.auditionWindow(for: region(start: 0, length: 0), bpm: 120,
                                                        transportPlaying: false))
    }

    func testAuditionWindow_negativeContentOffset_clampsToZero() {
        // Defensive: a corrupt/legacy negative trim never asks the file for time < 0.
        let r = region(start: 0, offset: -0.75)
        let w = AudioRegionPlayback.auditionWindow(for: r, bpm: 120, transportPlaying: false)
        XCTAssertEqual(w?.fromSeconds ?? -1, 0, accuracy: 1e-9)
    }

    func testAuditionWindow_lengthTracksTempo() {
        // The same 1920-tick region is 4.0 s @60 and 1.0 s @240 — musical length, not media length.
        let r = region(start: 0)
        XCTAssertEqual(AudioRegionPlayback.auditionWindow(for: r, bpm: 60,
                                                          transportPlaying: false)?.lengthSeconds ?? -1,
                       4.0, accuracy: 1e-9)
        XCTAssertEqual(AudioRegionPlayback.auditionWindow(for: r, bpm: 240,
                                                          transportPlaying: false)?.lengthSeconds ?? -1,
                       1.0, accuracy: 1e-9)
    }

    // MARK: - editWindow (CLIP-4: the trim window the EDIT door seeds)

    func testEditWindow_selectsTheRegionsMediaWindow() {
        // Trim-in 1.5 s, one bar @120 = 2.0 s → the door selects file [1.5, 3.5].
        let r = region(start: 1920, offset: 1.5)
        let w = AudioRegionPlayback.editWindow(for: r, bpm: 120)
        XCTAssertEqual(w?.startSeconds ?? -1, 1.5, accuracy: 1e-9)
        XCTAssertEqual(w?.endSeconds ?? -1, 3.5, accuracy: 1e-9)
    }

    func testEditWindow_badTempoOrEmptyRegion_isNil() {
        XCTAssertNil(AudioRegionPlayback.editWindow(for: region(start: 0), bpm: 0))
        XCTAssertNil(AudioRegionPlayback.editWindow(for: region(start: 0, length: 0), bpm: 120))
    }

    func testEditWindow_negativeOffset_clampsToZero() {
        let w = AudioRegionPlayback.editWindow(for: region(start: 0, offset: -2), bpm: 120)
        XCTAssertEqual(w?.startSeconds ?? -1, 0, accuracy: 1e-9)
    }

    // MARK: - regionTrim (CLIP-4: the EDIT door's write-back)

    func testRegionTrim_mapsWindowToOffsetAndTicks() {
        // File window [1.5, 3.5] @120 → offset 1.5 s, 2.0 s = one bar = 1920 ticks.
        let t = AudioRegionPlayback.regionTrim(startSeconds: 1.5, endSeconds: 3.5, bpm: 120)
        XCTAssertEqual(t?.contentOffsetSeconds ?? -1, 1.5, accuracy: 1e-9)
        XCTAssertEqual(t?.lengthTicks, 1920)
    }

    func testRegionTrim_roundTripsEditWindow() {
        // editWindow → regionTrim must reproduce the region's own media fields.
        let r = region(start: 0, length: 2880, offset: 0.75)   // 1.5 bars
        guard let w = AudioRegionPlayback.editWindow(for: r, bpm: 120),
              let t = AudioRegionPlayback.regionTrim(startSeconds: w.startSeconds,
                                                     endSeconds: w.endSeconds, bpm: 120) else {
            return XCTFail("mapping must exist for a valid region")
        }
        XCTAssertEqual(t.contentOffsetSeconds, 0.75, accuracy: 1e-9)
        XCTAssertEqual(t.lengthTicks, 2880)
    }

    func testRegionTrim_emptyOrInvertedWindow_isNil() {
        XCTAssertNil(AudioRegionPlayback.regionTrim(startSeconds: 2, endSeconds: 2, bpm: 120))
        XCTAssertNil(AudioRegionPlayback.regionTrim(startSeconds: 3, endSeconds: 1, bpm: 120))
        XCTAssertNil(AudioRegionPlayback.regionTrim(startSeconds: 0, endSeconds: 1, bpm: 0))
    }

    func testRegionTrim_negativeStart_clampsToZero_lengthAtLeastOneTick() {
        let t = AudioRegionPlayback.regionTrim(startSeconds: -1, endSeconds: 0.0001, bpm: 120)
        XCTAssertEqual(t?.contentOffsetSeconds ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(t?.lengthTicks, 1, "a sub-tick window still keeps one honest tick")
    }
}
