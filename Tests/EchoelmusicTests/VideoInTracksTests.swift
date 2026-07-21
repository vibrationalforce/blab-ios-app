// VideoInTracksTests.swift
// Echoel — pure, device-free video-in-tracks core: playhead→source-time sync,
// trim/duration math, the clip/region landing factory, the playability seam, and the
// bio-grade mapping + flash-safety clamp. No AVFoundation.

import XCTest
@testable import Echoelmusic

final class VideoInTracksTests: XCTestCase {

    // 480 PPQ; at 120 BPM one quarter = 0.5 s, so 1920 ticks (a bar) = 1.0 s.
    private let bpm = 120.0

    // MARK: - VideoRegionSync

    func testSync_beforeRegion_isInactive() {
        let r = VideoRegionSync.resolve(startTick: 1920, lengthTicks: 1920,
                                        contentOffsetSeconds: 0, bpm: bpm,
                                        nativeDurationSeconds: 10, playheadTick: 0)
        XCTAssertEqual(r, .inactive)
    }

    func testSync_atRegionStart_playsFromOffset() {
        let r = VideoRegionSync.resolve(startTick: 1920, lengthTicks: 1920,
                                        contentOffsetSeconds: 2.0, bpm: bpm,
                                        nativeDurationSeconds: 10, playheadTick: 1920)
        XCTAssertEqual(r, .play(sourceSeconds: 2.0))
    }

    func testSync_midRegion_addsElapsedSecondsAtTempo() {
        // 960 ticks into the region = 2 quarters = 1.0 s at 120 BPM (480 PPQ, so
        // seconds = ticks/480 * 60/bpm = 960/480 * 0.5 = 1.0). The prior "half a
        // quarter = 0.25 s" comment/expectation here was the test's own arithmetic
        // error (960 ticks is a HALF BAR, not a half quarter) — Sources' resolve()
        // matches TimelineTime.seconds(fromTicks:bpm:) exactly, verified against
        // the passing testFactory_regionSizedToTempo (2.0 s @120 BPM == 1920 ticks).
        let r = VideoRegionSync.resolve(startTick: 1920, lengthTicks: 1920,
                                        contentOffsetSeconds: 1.0, bpm: bpm,
                                        nativeDurationSeconds: 10, playheadTick: 1920 + 960)
        guard case let .play(s) = r else { return XCTFail("expected play") }
        XCTAssertEqual(s, 2.0, accuracy: 1e-9)
    }

    func testSync_pastRegionEnd_isInactive() {
        let r = VideoRegionSync.resolve(startTick: 0, lengthTicks: 1920,
                                        contentOffsetSeconds: 0, bpm: bpm,
                                        nativeDurationSeconds: 10, playheadTick: 1920)
        XCTAssertEqual(r, .inactive)   // endTick is exclusive
    }

    func testSync_mediaShorterThanSpan_isExhausted() {
        let r = VideoRegionSync.resolve(startTick: 0, lengthTicks: 1920,
                                        contentOffsetSeconds: 0, bpm: bpm,
                                        nativeDurationSeconds: 0.3, playheadTick: 960)
        guard case let .exhausted(s) = r else { return XCTFail("expected exhausted") }
        XCTAssertLessThan(s, 0.3)
        XCTAssertGreaterThan(s, 0.29)
    }

    func testSync_zeroDurationMedia_holdsAtOffset() {
        let r = VideoRegionSync.resolve(startTick: 0, lengthTicks: 480,
                                        contentOffsetSeconds: 4, bpm: bpm,
                                        nativeDurationSeconds: 0, playheadTick: 100)
        XCTAssertEqual(r, .exhausted(sourceSeconds: 4))
    }

    func testSync_isActive_boundaries() {
        XCTAssertFalse(VideoRegionSync.isActive(startTick: 10, lengthTicks: 5, playheadTick: 9))
        XCTAssertTrue(VideoRegionSync.isActive(startTick: 10, lengthTicks: 5, playheadTick: 10))
        XCTAssertTrue(VideoRegionSync.isActive(startTick: 10, lengthTicks: 5, playheadTick: 14))
        XCTAssertFalse(VideoRegionSync.isActive(startTick: 10, lengthTicks: 5, playheadTick: 15))
    }

    func testScrub_inactiveReturnsNil_activeMatchesResolve() throws {
        XCTAssertNil(VideoRegionSync.scrubSourceSeconds(
            startTick: 1920, lengthTicks: 1920, contentOffsetSeconds: 0, bpm: bpm,
            nativeDurationSeconds: 10, playheadTick: 0))
        // 960 ticks elapsed = 1.0 s at 120 BPM (see testSync_midRegion_… for the
        // same arithmetic correction) → offset 0.5 + elapsed 1.0 = 1.5.
        let active = try XCTUnwrap(VideoRegionSync.scrubSourceSeconds(
            startTick: 0, lengthTicks: 1920, contentOffsetSeconds: 0.5, bpm: bpm,
            nativeDurationSeconds: 10, playheadTick: 960))
        XCTAssertEqual(active, 1.5, accuracy: 1e-9)
    }

    // MARK: - VideoRegionTrim

    func testTrim_clampsInsideNative() {
        let t = VideoRegionTrim(nativeDurationSeconds: 5, trimInSeconds: -3, trimOutSeconds: 99)
        XCTAssertEqual(t.trimInSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(t.trimOutSeconds, 5, accuracy: 1e-9)
        XCTAssertEqual(t.trimmedDurationSeconds, 5, accuracy: 1e-9)
    }

    func testTrim_lengthTicksAtTempo() {
        // 2.0 s trimmed at 120 BPM: 2.0 s = 4 quarters = 4*480 = 1920 ticks.
        let t = VideoRegionTrim(nativeDurationSeconds: 10, trimInSeconds: 1, trimOutSeconds: 3)
        XCTAssertEqual(t.lengthTicks(atBPM: 120), 1920)
    }

    func testTrim_lengthTicks_neverZero() {
        let t = VideoRegionTrim(nativeDurationSeconds: 10)
        XCTAssertGreaterThanOrEqual(t.lengthTicks(atBPM: 0), 1)   // bpm guard
    }

    func testTrim_frameSnap() {
        XCTAssertEqual(VideoRegionTrim.snap(0.05, fps: 30), 2.0 / 30.0, accuracy: 1e-9)
        XCTAssertEqual(VideoRegionTrim.snap(1.234, fps: 0), 1.234, accuracy: 1e-9) // fps<=0 passthrough
    }

    func testTrim_setInOutKeepsOrdering() {
        var t = VideoRegionTrim(nativeDurationSeconds: 10, trimInSeconds: 2, trimOutSeconds: 8)
        t.setTrimIn(9)                 // would cross out → clamped below out
        XCTAssertLessThan(t.trimInSeconds, t.trimOutSeconds)
        t.setTrimOut(1)                // would cross in → clamped above in
        XCTAssertGreaterThan(t.trimOutSeconds, t.trimInSeconds)
    }

    func testTrim_roundTripCodable() throws {
        let t = VideoRegionTrim(nativeDurationSeconds: 12.5, trimInSeconds: 1.5, trimOutSeconds: 9)
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(VideoRegionTrim.self, from: data)
        XCTAssertEqual(t, back)
    }

    func testTrim_decodeMissingKeys_defaultsSafely() throws {
        let data = Data("{}".utf8)
        let back = try JSONDecoder().decode(VideoRegionTrim.self, from: data)
        XCTAssertGreaterThan(back.nativeDurationSeconds, 0)
        XCTAssertGreaterThan(back.trimmedDurationSeconds, 0)
    }

    // MARK: - VideoClipFactory

    func testFactory_makesVideoClip() {
        let c = VideoClipFactory.clip(name: "Take 1", mediaRef: "echoel_123.mp4")
        XCTAssertEqual(c.kind, .video)
        XCTAssertEqual(c.mediaRef, "echoel_123.mp4")
        XCTAssertFalse(c.isEmpty)         // media carriers are non-empty with a ref
    }

    func testFactory_regionSizedToTempo() {
        let lane = UUID(); let clip = UUID()
        let r = VideoClipFactory.region(forDurationSeconds: 2.0, bpm: 120,
                                        laneID: lane, clipID: clip, startTick: 480)
        XCTAssertEqual(r.laneID, lane)
        XCTAssertEqual(r.clipID, clip)
        XCTAssertEqual(r.startTick, 480)
        XCTAssertEqual(r.lengthTicks, 1920)   // 2 s @ 120 BPM
        XCTAssertEqual(r.contentOffsetSeconds, 0, accuracy: 1e-9)
    }

    func testFactory_regionHonoursTrimIn() {
        let r = VideoClipFactory.region(forDurationSeconds: 1.0, bpm: 120,
                                        laneID: UUID(), clipID: UUID(),
                                        startTick: 0, contentOffsetSeconds: 3)
        XCTAssertEqual(r.contentOffsetSeconds, 3, accuracy: 1e-9)
    }

    // MARK: - Playability seam

    func testPlayability_midiOnly_videoNotYet() {
        XCTAssertTrue(ClipKind.midi.isPlayable)
        XCTAssertFalse(ClipKind.video.isPlayable)     // engine not shipped → honest
        XCTAssertFalse(ClipKind.visual.isPlayable)
        XCTAssertEqual(ClipKind.timelineEngineKinds, [.midi])
    }

    func testMediaCarrier_classification() {
        XCTAssertFalse(ClipKind.midi.isMediaCarrier)
        XCTAssertTrue(ClipKind.audio.isMediaCarrier)
        XCTAssertTrue(ClipKind.video.isMediaCarrier)
        XCTAssertTrue(ClipKind.visual.isMediaCarrier)
    }

    // MARK: - videoLaneIDs + scheduling fan-out

    func testVideoLaneIDs_filtersKindAndBio() {
        let v1 = TimelineLane(name: "V1", kind: .video)
        let a1 = TimelineLane(name: "A1", kind: .audio)
        let vBio = TimelineLane(name: "VB", kind: .video, isBio: true)
        let doc = TimelineDocument(lanes: [v1, a1, vBio])
        XCTAssertEqual(doc.videoLaneIDs, [v1.id])
    }

    func testVideoLaneEvents_loadOnOnset() {
        let lane = TimelineLane(name: "V", kind: .video)
        let clip = UUID()
        let region = TimelineRegion(laneID: lane.id, clipID: clip,
                                    startTick: 1920, lengthTicks: 1920)
        let doc = TimelineDocument(lanes: [lane], regions: [region])
        let events = TimelineScheduling.videoLaneEvents(in: doc, fromTick: 1919, toTick: 1920)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].laneID, lane.id)
        XCTAssertEqual(events[0].event, .load(region))
    }

    // MARK: - BioColorGradeParams

    func testGrade_neutralAtZeroIntensity() {
        let g = BioColorGradeParams.from(coherence: 1, hrvNormalized: 1,
                                         breathPhase: 0.25, heartRateBPM: 120, intensity: 0)
        XCTAssertEqual(g.saturation, 1, accuracy: 1e-5)
        XCTAssertEqual(g.exposure, 1, accuracy: 1e-2)
        XCTAssertEqual(g.temperature, 0, accuracy: 1e-5)
        XCTAssertEqual(g.vignette, 0, accuracy: 1e-5)
    }

    func testGrade_coherenceLiftsSaturationAndWarmth() {
        let low = BioColorGradeParams.from(coherence: 0, hrvNormalized: 0.5,
                                           breathPhase: 0, heartRateBPM: 70)
        let high = BioColorGradeParams.from(coherence: 1, hrvNormalized: 0.5,
                                            breathPhase: 0, heartRateBPM: 70)
        XCTAssertGreaterThan(high.saturation, low.saturation)
        XCTAssertGreaterThan(high.temperature, low.temperature)
    }

    func testGrade_clampsToSafeRanges() {
        let g = BioColorGradeParams.from(coherence: 5, hrvNormalized: 9,
                                         breathPhase: 2, heartRateBPM: 500, intensity: 3)
        XCTAssert((0.5...1.5).contains(g.exposure))
        XCTAssert((0...2).contains(g.saturation))
        XCTAssert((0.5...1.5).contains(g.contrast))
        XCTAssert((-1...1).contains(g.temperature))
        XCTAssert((0...1).contains(g.vignette))
    }

    func testGrade_flashLimit_capsPerFrameDelta() {
        let prev = BioColorGradeParams.neutral
        var target = BioColorGradeParams.neutral
        target.exposure = 1.5
        let limited = target.flashLimited(from: prev, dt: 1.0 / 60.0, maxHz: 3)
        XCTAssertLessThanOrEqual(limited.exposure - prev.exposure, 0.1 + 1e-6)
    }

    func testGrade_flashLimit_passthroughWhenWithinBudget() {
        let prev = BioColorGradeParams.neutral
        var target = BioColorGradeParams.neutral
        target.saturation = 1.02
        let limited = target.flashLimited(from: prev, dt: 1.0 / 60.0)
        XCTAssertEqual(limited.saturation, 1.02, accuracy: 1e-6)
    }
}
