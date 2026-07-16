// AudioWarpMathTests.swift
// Echoel — task #54 Warp, slice S1 (pure core + persistence). Pins the ONE
// effective-rate truth (AudioRegionPlayback.effectiveStretchRate), the rate-aware
// media-time mapping, warp carry through split/trim/duplicate/join, and the
// document-safe decode of pre-warp clips/regions (fields absent → 0/false,
// bit-identical playback, nothing pruned). Pure value math — macOS SwiftPM CI.

import XCTest
@testable import Echoelmusic

final class AudioWarpMathTests: XCTestCase {

    private func region(start: Int = 0, length: Int = 1920, offset: Double = 0,
                        warp: Bool = false) -> TimelineRegion {
        TimelineRegion(laneID: UUID(), clipID: UUID(), startTick: start,
                       lengthTicks: length, contentOffsetSeconds: offset,
                       warpEnabled: warp)
    }

    // MARK: - effectiveStretchRate gates + clamp

    func testEffectiveStretchRate_gatesAndClamp() {
        // Warp off → exactly 1, whatever the tempi say.
        XCTAssertEqual(AudioRegionPlayback.effectiveStretchRate(
            warpEnabled: false, clipNativeBPM: 100, projectBPM: 120), 1.0)
        // Unknown native tempo → never warps.
        XCTAssertEqual(AudioRegionPlayback.effectiveStretchRate(
            warpEnabled: true, clipNativeBPM: 0, projectBPM: 120), 1.0)
        // Degenerate project tempo → never warps.
        XCTAssertEqual(AudioRegionPlayback.effectiveStretchRate(
            warpEnabled: true, clipNativeBPM: 100, projectBPM: 0), 1.0)
        // The musical case: 100 → 120 BPM plays 1.2× faster.
        XCTAssertEqual(AudioRegionPlayback.effectiveStretchRate(
            warpEnabled: true, clipNativeBPM: 100, projectBPM: 120), 1.2, accuracy: 1e-12)
        // Clamped to TempoMatch.rateRange (0.25…4.0) — a mis-set BPM stays musical.
        XCTAssertEqual(AudioRegionPlayback.effectiveStretchRate(
            warpEnabled: true, clipNativeBPM: 1000, projectBPM: 100), 0.25)
        XCTAssertEqual(AudioRegionPlayback.effectiveStretchRate(
            warpEnabled: true, clipNativeBPM: 20, projectBPM: 400), 4.0)
    }

    func testEffectiveStretchRate_agreesWithAudioClipRegionAuthority() {
        // ONE rate truth: the placed-region path must agree with the editor
        // model's effectiveStretchRate (which WarpedClipPlan delegates to).
        for (native, project) in [(87.5, 120.0), (100.0, 120.0), (174.0, 87.0), (60.0, 240.0)] {
            let editor = AudioClipRegion(startSeconds: 0, endSeconds: 4,
                                         warpEnabled: true, nativeBPM: native)
            XCTAssertEqual(
                AudioRegionPlayback.effectiveStretchRate(
                    warpEnabled: true, clipNativeBPM: native, projectBPM: project),
                editor.effectiveStretchRate(projectBPM: project),
                accuracy: 1e-12, "rate truths diverged at \(native)→\(project)")
        }
    }

    // MARK: - Rate-1 identity (today's behavior is bit-identical)

    func testRateOne_isIdenticalToTheUnwarpedFunctions() {
        let r = region(start: 480, length: 1920, offset: 0.75)
        let bpm = 120.0, sr = 48_000.0
        for tick in [480, 481, 1000, 2399] {
            XCTAssertEqual(
                AudioRegionPlayback.filePositionSeconds(for: r, atTick: tick, bpm: bpm),
                AudioRegionPlayback.filePositionSeconds(for: r, atTick: tick, bpm: bpm, stretchRate: 1.0))
            XCTAssertEqual(
                AudioRegionPlayback.startFrame(for: r, atTick: tick, bpm: bpm, sampleRate: sr),
                AudioRegionPlayback.startFrame(for: r, atTick: tick, bpm: bpm, sampleRate: sr, stretchRate: 1.0))
            XCTAssertEqual(
                AudioRegionPlayback.frameCount(for: r, fromTick: tick, bpm: bpm, sampleRate: sr),
                AudioRegionPlayback.frameCount(for: r, fromTick: tick, bpm: bpm, sampleRate: sr, stretchRate: 1.0))
        }
    }

    // MARK: - Rate-aware media mapping

    func testFilePosition_midRegionEntry_scalesElapsedByRate() {
        // 1920 ticks at 120 BPM = 2.0 song-seconds; entering at the half (960
        // ticks = 1.0 song-second) with rate 1.25 has consumed 1.25 media-seconds.
        let r = region(start: 0, length: 1920, offset: 0.5)
        let pos = AudioRegionPlayback.filePositionSeconds(for: r, atTick: 960,
                                                          bpm: 120, stretchRate: 1.25)
        XCTAssertEqual(pos ?? -1, 0.5 + 1.25, accuracy: 1e-9)
        // Outside the region stays nil, rate or not.
        XCTAssertNil(AudioRegionPlayback.filePositionSeconds(for: r, atTick: 1920,
                                                             bpm: 120, stretchRate: 1.25))
    }

    func testFrameCount_scalesSourceFramesByRate() {
        // 2.0 song-seconds of region at 48 kHz: rate 1 consumes 96 000 source
        // frames; rate 1.25 consumes 120 000 (faster playback eats more media);
        // rate 0.5 consumes 48 000 (stretched, less media per song-second).
        let r = region(start: 0, length: 1920)
        XCTAssertEqual(AudioRegionPlayback.frameCount(for: r, fromTick: 0, bpm: 120,
                                                      sampleRate: 48_000), 96_000)
        XCTAssertEqual(AudioRegionPlayback.frameCount(for: r, fromTick: 0, bpm: 120,
                                                      sampleRate: 48_000, stretchRate: 1.25), 120_000)
        XCTAssertEqual(AudioRegionPlayback.frameCount(for: r, fromTick: 0, bpm: 120,
                                                      sampleRate: 48_000, stretchRate: 0.5), 48_000)
    }

    func testDegenerateRates_fallBackToUnity() {
        let r = region(start: 0, length: 1920, offset: 0.25)
        for bad in [0.0, -1.0, Double.nan, Double.infinity] {
            XCTAssertEqual(
                AudioRegionPlayback.filePositionSeconds(for: r, atTick: 960, bpm: 120, stretchRate: bad),
                AudioRegionPlayback.filePositionSeconds(for: r, atTick: 960, bpm: 120),
                "rate \(bad) must behave as 1.0, never corrupt the mapping")
            XCTAssertEqual(
                AudioRegionPlayback.frameCount(for: r, fromTick: 0, bpm: 120, sampleRate: 48_000, stretchRate: bad),
                96_000)
        }
    }

    func testFrameIdentity_agreesWithWarpedClipPlan() {
        // Cross-check against the tested reference: a clip whose SOURCE window is
        // 2.5 s at rate 1.25 occupies 2.0 SONG-seconds (= 1920 ticks at 120 BPM).
        // The placed-region path must consume exactly the plan's source frames.
        let sr = 48_000.0
        let editor = AudioClipRegion(startSeconds: 0, endSeconds: 2.5,
                                     warpEnabled: true, nativeBPM: 96)   // 96→120 = ×1.25
        let plan = WarpedClipPlan(region: editor, startTick: 0, projectBPM: 120,
                                  engineSampleRate: sr)
        XCTAssertEqual(plan.stretchRate, 1.25, accuracy: 1e-12)
        XCTAssertEqual(plan.sourceFrameCount, 120_000)
        XCTAssertEqual(plan.outputFrameCount, 96_000)
        let r = region(start: 0, length: 1920)
        XCTAssertEqual(
            AudioRegionPlayback.frameCount(for: r, fromTick: 0, bpm: 120,
                                           sampleRate: sr, stretchRate: plan.stretchRate),
            plan.sourceFrameCount,
            "placed-region source consumption must match the WarpedClipPlan identity")
    }

    // MARK: - Warp carry through region edits

    func testSplit_carriesWarpToBothPieces_andJoinRestores() {
        let r = region(start: 0, length: 1920, warp: true)
        guard let (a, b) = r.split(at: 960, bpm: 120) else { return XCTFail("split failed") }
        XCTAssertTrue(a.warpEnabled)
        XCTAssertTrue(b.warpEnabled)
        XCTAssertTrue(a.abuts(b, bpm: 120), "a clean split must stay joinable")
        XCTAssertTrue(a.merged(with: b).warpEnabled)
    }

    func testAbuts_refusesWarpMismatch() {
        let r = region(start: 0, length: 1920, warp: true)
        guard let (a, b) = r.split(at: 960, bpm: 120) else { return XCTFail("split failed") }
        var cold = b
        cold.warpEnabled = false
        XCTAssertFalse(a.abuts(cold, bpm: 120),
                       "joining warped onto unwarped would silently pick one state — refuse")
    }

    func testTrimAndDuplicate_keepWarp() {
        let r = region(start: 480, length: 1920, offset: 1.0, warp: true)
        XCTAssertEqual(r.trimmedStart(toTick: 960, bpm: 120)?.warpEnabled, true)
        XCTAssertTrue(r.duplicated().warpEnabled)
    }

    // MARK: - Document safety (decodeIfPresent, nothing pruned)

    func testLegacyRegionDecodes_warpFalse_andRoundTrips() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","laneID":"\(UUID().uuidString)",
         "clipID":"\(UUID().uuidString)","startTick":0,"lengthTicks":960}
        """
        let old = try JSONDecoder().decode(TimelineRegion.self, from: Data(legacy.utf8))
        XCTAssertFalse(old.warpEnabled, "pre-warp documents must load bit-identical")

        let warped = region(warp: true)
        let back = try JSONDecoder().decode(TimelineRegion.self,
                                            from: JSONEncoder().encode(warped))
        XCTAssertTrue(back.warpEnabled, "warp must persist with the document")
    }

    func testLegacyClipDecodes_nativeBPMZero_andRoundTrips() throws {
        let legacy = #"{"name":"Old loop","kind":"audio","mediaRef":"loop.wav"}"#
        let old = try JSONDecoder().decode(Clip.self, from: Data(legacy.utf8))
        XCTAssertEqual(old.nativeBPM, 0, "unknown tempo → never warps, nothing invented")

        let clip = Clip(name: "Jungle", kind: .audio, mediaRef: "j.wav", nativeBPM: 174)
        let back = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip))
        XCTAssertEqual(back.nativeBPM, 174, accuracy: 1e-12)
    }

    func testClipNativeBPM_clampsLikeTheEditorModel() {
        XCTAssertEqual(Clip(name: "x", nativeBPM: 500).nativeBPM, 400)   // upper musical bound
        XCTAssertEqual(Clip(name: "x", nativeBPM: 5).nativeBPM, 20)     // lower musical bound
        XCTAssertEqual(Clip(name: "x", nativeBPM: -3).nativeBPM, 0)     // nonsense → unknown
        XCTAssertEqual(Clip(name: "x", nativeBPM: .nan).nativeBPM, 0)   // NaN → unknown
        XCTAssertEqual(Clip(name: "x").nativeBPM, 0)                    // default = unknown
    }
}
