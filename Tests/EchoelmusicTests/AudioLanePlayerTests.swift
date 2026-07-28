// AudioLanePlayerTests.swift
// The transport-driven AUDIO-lane executor's mapping logic, tested via a spy sink
// (no AVFoundation). Pins: onset → play with the right file position + remaining
// length + gain; leaving a region → stop; unchanged → nothing; muted/unresolvable
// → no play. Reference: 1 bar = 1920 ticks = 2.0 s @120 BPM.

import XCTest
@testable import Echoelmusic

@MainActor
final class AudioLanePlayerTests: XCTestCase {

    // MARK: - Spy sink + factory

    final class SpySink: AudioRegionSink {
        struct Play: Equatable {
            let url: URL; let from: Double; let length: Double; let gain: Float
            let stretch: StretchPlan
        }
        var plays: [Play] = []
        var stops = 0
        var preloads: [URL] = []
        /// Slice B: the `warped` flag passed with each preload, parallel to `preloads`.
        var preloadWarps: [Bool] = []
        var detaches = 0
        var gains: [Float] = []
        var pans: [Float] = []
        func play(url: URL, fromSeconds: Double, lengthSeconds: Double, gain: Float,
                  stretch: StretchPlan) {
            plays.append(Play(url: url, from: fromSeconds, length: lengthSeconds,
                              gain: gain, stretch: stretch))
        }
        func stop() { stops += 1 }
        func preload(url: URL, warped: Bool) {
            preloads.append(url)
            preloadWarps.append(warped)
        }
        func detach() { detaches += 1 }
        func setGain(_ gain: Float) { gains.append(gain) }
        func setPan(_ pan: Float) { pans.append(pan) }
        /// Beats-Executor: the prime-time pre-render requests, in call order.
        struct BeatsPrep: Equatable {
            let url: URL; let from: Double; let length: Double; let rate: Double
        }
        var beatsPreps: [BeatsPrep] = []
        func prepareBeats(url: URL, fromSeconds: Double, lengthSeconds: Double, rate: Double) {
            beatsPreps.append(BeatsPrep(url: url, from: fromSeconds,
                                        length: lengthSeconds, rate: rate))
        }
    }

    /// `@MainActor` is explicit rather than inferred (#142). A nested type does NOT inherit
    /// the enclosing type's global-actor isolation, so `Factory` was non-isolated while the
    /// `SpySink` it constructs infers `@MainActor` from `AudioRegionSink`. Two toolchains
    /// disagreed about whether that is an error — SwiftPM compiles this target as Swift 5
    /// with no strict concurrency, Xcode as Swift 6 — which is the worst possible state:
    /// a file whose validity depends on which gate happens to look at it. Annotating costs
    /// nothing today and settles it in both.
    @MainActor
    final class Factory {
        var sinks: [SpySink] = []
        func make() -> AudioRegionSink { let s = SpySink(); sinks.append(s); return s }
    }

    private let fileURL = URL(fileURLWithPath: "/tmp/echoel-test.wav")

    /// A doc with one audio lane carrying a one-bar region at `start`, media trim `offset`.
    private func doc(start: Int = 0, length: Int = 1920, offset: Double = 0,
                     muted: Bool = false) -> (TimelineDocument, UUID) {
        let lane = TimelineLane(name: "Audio 1", kind: .audio, isMuted: muted)
        let region = TimelineRegion(laneID: lane.id, clipID: UUID(), startTick: start,
                                    lengthTicks: length, contentOffsetSeconds: offset)
        return (TimelineDocument(lanes: [lane], regions: [region]), lane.id)
    }

    private func player(_ factory: Factory, resolve: @escaping (UUID) -> URL?,
                        nativeBPM: @escaping (UUID) -> Double = { _ in 0 }) -> AudioLanePlayer {
        AudioLanePlayer(makeSink: factory.make, resolveURL: resolve,
                        resolveNativeBPM: nativeBPM)
    }

    // MARK: - Onset

    func testOnset_playsFromContentOffset_forFullRegionLength() {
        let (document, _) = doc(offset: 1.5)
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        // Cross into the region: fromTick before its start, toTick at its start.
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)

        XCTAssertEqual(factory.sinks.count, 1, "one sink created for the audio lane")
        XCTAssertEqual(factory.sinks.first?.plays.count, 1)
        let play = try? XCTUnwrap(factory.sinks.first?.plays.first)
        XCTAssertEqual(play?.url, fileURL)
        XCTAssertEqual(play?.from ?? -1, 1.5, accuracy: 1e-9, "starts at the trim-in point")
        XCTAssertEqual(play?.length ?? -1, 2.0, accuracy: 1e-9, "plays the whole bar (2.0 s @120)")
        XCTAssertEqual(play?.gain ?? -1, 1.0, accuracy: 1e-6, "default lane level")
    }

    func testOnset_regionGain_multipliesLaneGain() {
        // CLIP-6: a 0.5-gain region on a 0.8-level lane plays at 0.4 — the
        // editor's Gain finally reaches the song instead of being dropped.
        let lane = TimelineLane(name: "Audio 1", kind: .audio, level: 0.8)
        var placed = TimelineRegion(laneID: lane.id, clipID: UUID(),
                                    startTick: 0, lengthTicks: 1920)
        placed.gain = 0.5
        let document = TimelineDocument(lanes: [lane], regions: [placed])
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)
        let play = try? XCTUnwrap(factory.sinks.first?.plays.first)
        XCTAssertEqual(play?.gain ?? -1, 0.4, accuracy: 1e-6)
    }

    func testZeroGainRegion_isSilent_untilGainReturns() {
        // A 0-gain region gates like a mute; raising the region gain mid-region
        // (reconcile path) restarts the lane at the honest file position.
        let lane = TimelineLane(name: "Audio 1", kind: .audio)
        var placed = TimelineRegion(laneID: lane.id, clipID: UUID(),
                                    startTick: 0, lengthTicks: 1920)
        placed.gain = 0
        var document = TimelineDocument(lanes: [lane], regions: [placed])
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.prime(in: document, atTick: 0, bpm: 120)   // warms the sink; 0-gain stays silent
        XCTAssertTrue(factory.sinks.first?.plays.isEmpty ?? true, "0-gain region never plays")

        document.regions[0].gain = 1
        p.apply(in: document, fromTick: 0, toTick: 480, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.plays.count, 1, "gain returning starts the region")
        XCTAssertEqual(factory.sinks.first?.plays.first?.from ?? -1, 0.5, accuracy: 1e-9,
                       "restart lands at the honest mid-region file position")
    }

    func testOnset_midRegionEntry_advancesFilePosition() {
        let (document, _) = doc(offset: 1.0)
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        // Enter 480 ticks (0.5 s @120) into the region (a seek/loop landing).
        p.prime(in: document, atTick: 480, bpm: 120)
        let play = try? XCTUnwrap(factory.sinks.first?.plays.first)
        XCTAssertEqual(play?.from ?? -1, 1.5, accuracy: 1e-9, "offset + elapsed")
        XCTAssertEqual(play?.length ?? -1, 1.5, accuracy: 1e-9, "remaining 1440 ticks = 1.5 s")
    }

    // MARK: - Clear / unchanged

    func testLeavingRegion_stops() {
        let (document, _) = doc()
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)     // onset → play + create sink
        XCTAssertEqual(factory.sinks.first?.plays.count, 1)
        // Move the playhead past the region's end into a gap.
        p.apply(in: document, fromTick: 0, toTick: 5000, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.stops, 1, "leaving the region stops the sink")
    }

    func testUnchanged_doesNothing() {
        let (document, _) = doc()
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)     // onset → play once
        p.apply(in: document, fromTick: 0, toTick: 480, bpm: 120)    // same region → unchanged
        XCTAssertEqual(factory.sinks.first?.plays.count, 1, "no re-trigger while inside the same region")
        XCTAssertEqual(factory.sinks.first?.stops, 0)
    }

    // MARK: - Gating

    func testMutedLane_neverPlays() {
        let (document, _) = doc(muted: true)
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)
        XCTAssertTrue(factory.sinks.isEmpty, "a muted lane never reaches the play path")
    }

    func testUnresolvableFile_neverPlays() {
        let (document, _) = doc()
        let factory = Factory()
        let p = player(factory) { _ in nil }   // no URL for any clip
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)
        XCTAssertTrue(factory.sinks.first?.plays.isEmpty ?? true, "no file ⇒ no playback")
    }

    // MARK: - Warm-up + teardown (audio-thread review on the wiring cycle)

    func testPrime_preloadsEveryDistinctFile_notJustTheEarliest() {
        // PERF-01: a lane mixing two different files must have BOTH warmed at
        // prime — the sink attaches one node per distinct format, so their
        // boundary crosses with no mid-song engine pause.
        let lane = TimelineLane(name: "Audio 1", kind: .audio)
        let clipA = UUID(), clipB = UUID()
        let urlA = URL(fileURLWithPath: "/tmp/echoel-a.wav")
        let urlB = URL(fileURLWithPath: "/tmp/echoel-b.wav")
        let document = TimelineDocument(lanes: [lane], regions: [
            TimelineRegion(laneID: lane.id, clipID: clipA, startTick: 0, lengthTicks: 1920),
            TimelineRegion(laneID: lane.id, clipID: clipB, startTick: 1920, lengthTicks: 1920),
            TimelineRegion(laneID: lane.id, clipID: clipA, startTick: 3840, lengthTicks: 1920),
        ])
        let factory = Factory()
        let p = player(factory) { id in id == clipA ? urlA : urlB }
        p.prime(in: document, atTick: 0, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.preloads, [urlA, urlB],
                       "every distinct file warms once, in lane order — no duplicates")
    }

    func testPrime_preloadsLateStartingLane_withoutPlayingIt() {
        // The lane's only region starts at bar 2 — inactive at tick 0. Prime must
        // still PRELOAD it (attach happens before playback; a lazy attach at the
        // bar-2 onset would pause the whole engine mid-song) but not play it.
        let (document, _) = doc(start: 1920)
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.prime(in: document, atTick: 0, bpm: 120)
        XCTAssertEqual(factory.sinks.count, 1)
        XCTAssertEqual(factory.sinks.first?.preloads, [fileURL])
        XCTAssertTrue(factory.sinks.first?.plays.isEmpty ?? false, "warm-up must not sound")
    }

    func testPrime_firstClipUnresolvable_stillWarmsTheLaneFromALaterRegion() {
        // The earliest region's file is missing; a later region's resolves. Prime
        // must still attach/warm the lane NOW — otherwise the later onset (or an
        // unmute) attaches mid-song and pauses the whole engine (H4 review MEDIUM).
        let lane = TimelineLane(name: "Audio 1", kind: .audio)
        let missing = UUID(), present = UUID()
        let document = TimelineDocument(lanes: [lane], regions: [
            TimelineRegion(laneID: lane.id, clipID: missing, startTick: 0, lengthTicks: 1920),
            TimelineRegion(laneID: lane.id, clipID: present, startTick: 3840, lengthTicks: 1920),
        ])
        let factory = Factory()
        let p = player(factory) { id in id == present ? self.fileURL : nil }
        p.prime(in: document, atTick: 0, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.preloads, [fileURL],
                       "warm-up falls through to the first RESOLVABLE region")
    }

    func testRemovedLane_reconcileDetachesItsSink() {
        let (document, _) = doc()
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)     // creates + plays
        p.apply(in: TimelineDocument(), fromTick: 0, toTick: 480, bpm: 120)   // lane gone
        XCTAssertEqual(factory.sinks.first?.stops, 1)
        XCTAssertEqual(factory.sinks.first?.detaches, 1, "the engine node is released, not just stopped")
    }

    // MARK: - H4 live mixer (mid-region gain/pan — closes this file's KNOWN GAP)

    /// The same doc with a mixer edit applied to its (single) audio lane.
    private func edited(_ document: TimelineDocument,
                        level: Float? = nil, muted: Bool? = nil,
                        pan: Float? = nil) -> TimelineDocument {
        var d = document
        if let level { d.lanes[0].level = level }
        if let muted { d.lanes[0].isMuted = muted }
        if let pan { d.lanes[0].pan = pan }
        return d
    }

    func testLiveLevelEdit_midRegion_reGainsWithoutRestart() {
        let (document, _) = doc()
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)              // onset at level 1
        p.apply(in: edited(document, level: 0.5), fromTick: 0, toTick: 480, bpm: 120)
        let sink = factory.sinks.first
        XCTAssertEqual(sink?.plays.count, 1, "a level move must NOT re-schedule the file")
        XCTAssertEqual(sink?.gains.last ?? -1, 0.5, accuracy: 1e-6)
        // Same value again → no duplicate push.
        let gainPushes = sink?.gains.count ?? -1
        p.apply(in: edited(document, level: 0.5), fromTick: 480, toTick: 960, bpm: 120)
        XCTAssertEqual(sink?.gains.count, gainPushes, "unchanged mixer ⇒ no sink traffic")
    }

    func testMute_midRegion_stops_andUnmuteRestartsAtHonestPosition() {
        let (document, _) = doc(offset: 1.0)
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)              // onset
        p.apply(in: edited(document, muted: true), fromTick: 0, toTick: 480, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.stops, 1, "mute mid-region silences now, not at the boundary")
        // Unmute 960 ticks (1.0 s @120) into the region: the one-shot segment is
        // gone, so the lane must RE-START from the honest file position.
        p.apply(in: document, fromTick: 480, toTick: 960, bpm: 120)
        let sink = factory.sinks.first
        XCTAssertEqual(sink?.plays.count, 2)
        XCTAssertEqual(sink?.plays.last?.from ?? -1, 2.0, accuracy: 1e-9, "offset 1.0 + elapsed 1.0")
        XCTAssertEqual(sink?.plays.last?.length ?? -1, 1.0, accuracy: 1e-9, "remaining 960 ticks")
    }

    func testMutedAtOnset_unmuteMidRegion_startsTheLane() {
        // The onset gate stopped a muted lane; a mid-region unmute must still start it.
        let (document, _) = doc(muted: true)
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.prime(in: document, atTick: 0, bpm: 120)                            // muted ⇒ silent
        XCTAssertTrue(factory.sinks.first?.plays.isEmpty ?? true)
        p.apply(in: edited(document, muted: false), fromTick: 0, toTick: 480, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.plays.count, 1, "unmute inside the region starts playback")
        XCTAssertEqual(factory.sinks.first?.plays.first?.from ?? -1, 0.5, accuracy: 1e-9,
                       "starts at the elapsed position (480 ticks = 0.5 s), not the region top")
    }

    // MARK: - Stretch Slice B (timeline applies the region's StretchPlan)

    func testWarpedRegion_rateAwarePositionLengthAndPlan() {
        // Native 60 BPM media in a 120 BPM song → rate 2.0 (media consumed 2× as
        // fast). Enter 480 ticks (0.5 song-s) into a warped Tape region with a
        // 1.0 s trim-in: file position = 1.0 + 0.5·2 = 2.0 s; remaining 1440
        // ticks (1.5 song-s) schedule 3.0 s of MEDIA. Tape ⇒ pitch rides tempo.
        let lane = TimelineLane(name: "Audio 1", kind: .audio)
        let region = TimelineRegion(laneID: lane.id, clipID: UUID(), startTick: 0,
                                    lengthTicks: 1920, contentOffsetSeconds: 1.0,
                                    warpEnabled: true, stretchMode: .tape)
        let document = TimelineDocument(lanes: [lane], regions: [region])
        let factory = Factory()
        let p = player(factory, resolve: { _ in self.fileURL }, nativeBPM: { _ in 60 })
        p.prime(in: document, atTick: 480, bpm: 120)
        let play = try? XCTUnwrap(factory.sinks.first?.plays.first)
        XCTAssertEqual(play?.stretch.rate ?? -1, 2.0, accuracy: 1e-9)
        XCTAssertEqual(play?.stretch.preservesPitch, false, "Tape lets pitch ride the tempo")
        XCTAssertEqual(play?.stretch.mode, .tape)
        XCTAssertEqual(play?.from ?? -1, 2.0, accuracy: 1e-9, "offset + elapsed·rate")
        XCTAssertEqual(play?.length ?? -1, 3.0, accuracy: 1e-9, "media = song-seconds × rate")
    }

    func testUnwarpedRegion_playsPlanRateOne_pitchHeld() {
        // The default (no warp) is bit-identical to pre-Slice-B: rate 1.0, Clean.
        let (document, _) = doc()
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)
        let play = try? XCTUnwrap(factory.sinks.first?.plays.first)
        XCTAssertEqual(play?.stretch.rate ?? -1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(play?.stretch.preservesPitch, true)
        XCTAssertEqual(play?.stretch.mode, .clean)
    }

    func testWarpedRegion_unknownNativeBPM_honestlyUnstretched() {
        // Warp ON but the clip's tempo is unknown (resolver returns 0) → rate 1.0,
        // exactly like the editor preview — never a guessed stretch.
        let lane = TimelineLane(name: "Audio 1", kind: .audio)
        let region = TimelineRegion(laneID: lane.id, clipID: UUID(), startTick: 0,
                                    lengthTicks: 1920, warpEnabled: true, stretchMode: .tape)
        let document = TimelineDocument(lanes: [lane], regions: [region])
        let factory = Factory()
        let p = player(factory, resolve: { _ in self.fileURL })   // nativeBPM stays 0
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)
        let play = try? XCTUnwrap(factory.sinks.first?.plays.first)
        XCTAssertEqual(play?.stretch.rate ?? -1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(play?.length ?? -1, 2.0, accuracy: 1e-9, "unstretched bar length")
    }

    func testPrime_marksWarpNeedPerURL_orMergedAcrossRegions() {
        // One file placed unwarped AND warped on the same lane: its single preload
        // must carry warped=true (OR-merge) so the sink attaches the warp chain at
        // prime time, never mid-song. A second, never-warped file stays false.
        let lane = TimelineLane(name: "Audio 1", kind: .audio)
        let clipA = UUID(), clipB = UUID()
        let urlA = URL(fileURLWithPath: "/tmp/echoel-a.wav")
        let urlB = URL(fileURLWithPath: "/tmp/echoel-b.wav")
        let document = TimelineDocument(lanes: [lane], regions: [
            TimelineRegion(laneID: lane.id, clipID: clipA, startTick: 0, lengthTicks: 1920),
            TimelineRegion(laneID: lane.id, clipID: clipB, startTick: 1920, lengthTicks: 1920),
            TimelineRegion(laneID: lane.id, clipID: clipA, startTick: 3840, lengthTicks: 1920,
                           warpEnabled: true, stretchMode: .clean),
        ])
        let factory = Factory()
        let p = player(factory, resolve: { id in id == clipA ? urlA : urlB },
                       nativeBPM: { id in id == clipA ? 90 : 0 })
        p.prime(in: document, atTick: 0, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.preloads, [urlA, urlB], "still one preload per file")
        XCTAssertEqual(factory.sinks.first?.preloadWarps, [true, false],
                       "warp need OR-merges across a file's regions")
    }

    // MARK: - Beats-Executor (timeline pre-renders Beats at prime time)

    func testPrime_preRendersBeatsRegion_withMediaWindowAndRate() {
        // Native 100 BPM media in a 120 BPM song → rate 1.2. One-bar region
        // (2.0 song-s @120) with a 0.5 s trim-in: the sink must be asked to
        // pre-render media 0.5 s → +2.4 s (song-seconds × rate) at rate 1.2.
        let lane = TimelineLane(name: "Audio 1", kind: .audio)
        let region = TimelineRegion(laneID: lane.id, clipID: UUID(), startTick: 0,
                                    lengthTicks: 1920, contentOffsetSeconds: 0.5,
                                    warpEnabled: true, stretchMode: .beats)
        let document = TimelineDocument(lanes: [lane], regions: [region])
        let factory = Factory()
        let p = player(factory, resolve: { _ in self.fileURL }, nativeBPM: { _ in 100 })
        p.prime(in: document, atTick: 0, bpm: 120)
        let prep = try? XCTUnwrap(factory.sinks.first?.beatsPreps.first)
        XCTAssertEqual(factory.sinks.first?.beatsPreps.count, 1)
        XCTAssertEqual(prep?.url, fileURL)
        XCTAssertEqual(prep?.from ?? -1, 0.5, accuracy: 1e-9, "media window starts at the trim-in")
        XCTAssertEqual(prep?.length ?? -1, 2.4, accuracy: 1e-9, "media = song-seconds × rate")
        XCTAssertEqual(prep?.rate ?? -1, 1.2, accuracy: 1e-9)
        // And the onset resolves Beats AS Beats on the timeline now (the sink
        // decides buffer vs honest Clean fallback at play time).
        let play = try? XCTUnwrap(factory.sinks.first?.plays.first)
        XCTAssertEqual(play?.stretch.mode, .beats)
        XCTAssertEqual(play?.stretch.rate ?? -1, 1.2, accuracy: 1e-9)
        XCTAssertEqual(play?.stretch.preservesPitch, true, "Beats holds pitch")
    }

    func testPrime_skipsBeatsPreRender_forCleanTapeUnwarpedOrUnknownTempo() {
        let lane = TimelineLane(name: "Audio 1", kind: .audio)
        let clipTape = UUID(), clipPlain = UUID(), clipNoBPM = UUID()
        let document = TimelineDocument(lanes: [lane], regions: [
            TimelineRegion(laneID: lane.id, clipID: clipTape, startTick: 0,
                           lengthTicks: 1920, warpEnabled: true, stretchMode: .tape),
            TimelineRegion(laneID: lane.id, clipID: clipPlain, startTick: 1920,
                           lengthTicks: 1920, stretchMode: .beats),          // warp OFF
            TimelineRegion(laneID: lane.id, clipID: clipNoBPM, startTick: 3840,
                           lengthTicks: 1920, warpEnabled: true, stretchMode: .beats),
        ])
        let factory = Factory()
        let p = player(factory, resolve: { _ in self.fileURL },
                       nativeBPM: { id in id == clipNoBPM ? 0 : 100 })   // no tempo → rate 1
        p.prime(in: document, atTick: 0, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.beatsPreps.count ?? -1, 0,
                       "only warped Beats regions with a known tempo pre-render")
    }

    func testPan_appliedAtOnset_andLiveEdit() {
        var (document, _) = doc()
        document.lanes[0].pan = 0.5
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.pans.last ?? -1, 0.5, accuracy: 1e-6, "pan set at onset")
        p.apply(in: edited(document, pan: -1), fromTick: 0, toTick: 480, bpm: 120)
        // ⛔ The nil sentinel here used to be `?? -1` — the SAME value as the expectation,
        // so this assertion could not fail (#140). An empty `sinks`, or a `pans` that never
        // received the live edit — precisely the regression this line exists to catch —
        // produced -1 and passed. `.nan` is the correct sentinel for an `accuracy:` compare,
        // because NaN fails every comparison, so "no value" can never look like the value.
        // The other 28 `?? -1` sites in this file are fine: their expectations are all ≠ -1.
        XCTAssertEqual(factory.sinks.first?.pans.last ?? .nan, -1, accuracy: 1e-6, "live pan edit lands")
        XCTAssertEqual(factory.sinks.first?.plays.count, 1, "pan never re-schedules")
    }

    // MARK: - Clip-Launch override (S1 of PLAN_AUDIO_CLIP_LAUNCH)

    /// A launched override plays its region from the content top and reports itself.
    func testLaunchOverride_startsFromTop_andReportsOverriding() {
        let (document, laneID) = doc(offset: 1.5)
        let region = document.regions[0]
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        XCTAssertFalse(p.hasLaunchOverrides)
        p.setLaunchOverride(region, laneID: laneID, atTick: 0, in: document, bpm: 120)
        XCTAssertTrue(p.hasLaunchOverrides)
        XCTAssertTrue(p.isLaunchOverriding(laneID))
        let plays = factory.sinks.first?.plays ?? []
        XCTAssertEqual(plays.count, 1)
        XCTAssertEqual(plays.first?.from ?? -1, 1.5, accuracy: 1e-6,
                       "launched clip plays from its content offset (the top)")
    }

    /// The one-shot audio segment is RE-TRIGGERED when the loop wraps (a launched
    /// clip loops; MIDI re-windows for free, audio must re-schedule).
    func testLaunchOverride_loopWrap_reTriggers() {
        // offset 1.5 ⇒ the re-trigger `from` must equal the content offset, so a
        // wrong-offset regression can't hide behind a 0 that also means "top".
        let (document, laneID) = doc(length: 1920, offset: 1.5)   // 1 bar loop
        let region = document.regions[0]
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.setLaunchOverride(region, laneID: laneID, atTick: 0, in: document, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.plays.count, 1)
        // Cross the 1920 loop boundary → the segment re-starts from the top.
        p.apply(in: document, fromTick: 1900, toTick: 1940, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.plays.count, 2, "loop wrap re-triggers the segment")
        XCTAssertEqual(factory.sinks.first?.plays.last?.from ?? -1, 1.5, accuracy: 1e-6,
                       "re-trigger restarts at the region content top (its offset)")
    }

    /// Inside the loop (no wrap, no mixer edit) the launched lane does nothing —
    /// the segment keeps playing, not re-scheduled every step.
    func testLaunchOverride_withinLoop_doesNotReTrigger() {
        let (document, laneID) = doc(length: 1920, offset: 1.5)
        let region = document.regions[0]
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.setLaunchOverride(region, laneID: laneID, atTick: 0, in: document, bpm: 120)
        p.apply(in: document, fromTick: 100, toTick: 200, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.plays.count, 1, "no wrap ⇒ no re-trigger")
        XCTAssertEqual(factory.sinks.first?.stops, 0)
    }

    /// Clearing the override hands the lane back to the arrangement region active now,
    /// at the HONEST file position for that tick (480 ticks = 0.5 s @120 BPM).
    func testClearLaunchOverride_returnsToArrangement() {
        let (document, laneID) = doc(length: 1920)
        let region = document.regions[0]
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.setLaunchOverride(region, laneID: laneID, atTick: 0, in: document, bpm: 120)
        p.clearLaunchOverride(laneID: laneID, atTick: 480, in: document, bpm: 120)
        XCTAssertFalse(p.isLaunchOverriding(laneID))
        XCTAssertFalse(p.hasLaunchOverrides)
        XCTAssertEqual(factory.sinks.first?.plays.count, 2,
                       "clear restarts the arrangement region at the current tick")
        XCTAssertEqual(factory.sinks.first?.plays.last?.from ?? -1, 0.5, accuracy: 1e-6,
                       "the arrangement resumes at the honest file position for tick 480")
    }

    /// Replacing the override with a DIFFERENT region on the same lane launches the
    /// new region from ITS content top (last tap wins).
    func testSetLaunchOverride_replaceWithDifferentRegion() {
        let lane = TimelineLane(name: "Audio 1", kind: .audio)
        let regionA = TimelineRegion(laneID: lane.id, clipID: UUID(),
                                     startTick: 0, lengthTicks: 1920, contentOffsetSeconds: 0)
        let regionB = TimelineRegion(laneID: lane.id, clipID: UUID(),
                                     startTick: 1920, lengthTicks: 1920, contentOffsetSeconds: 1.0)
        let document = TimelineDocument(lanes: [lane], regions: [regionA, regionB])
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.setLaunchOverride(regionA, laneID: lane.id, atTick: 0, in: document, bpm: 120)
        p.setLaunchOverride(regionB, laneID: lane.id, atTick: 0, in: document, bpm: 120)
        XCTAssertTrue(p.isLaunchOverriding(lane.id))
        XCTAssertEqual(factory.sinks.first?.plays.count, 2)
        XCTAssertEqual(factory.sinks.first?.plays.last?.from ?? -1, 1.0, accuracy: 1e-6,
                       "replacing the override launches the new region from its top")
    }

    /// The #22 silence surface: unmute a muted, looping launched clip and it resumes
    /// at the honest loop PHASE (not the top) — the un-silence branch of the mixer.
    func testLaunchOverride_unmuteResumesAtLoopPhase() {
        let lane = TimelineLane(name: "Audio 1", kind: .audio)
        let region = TimelineRegion(laneID: lane.id, clipID: UUID(),
                                    startTick: 0, lengthTicks: 1920)
        let docOn = TimelineDocument(lanes: [lane], regions: [region])
        var mutedLane = lane; mutedLane.isMuted = true
        let docMuted = TimelineDocument(lanes: [mutedLane], regions: [region])
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.setLaunchOverride(region, laneID: lane.id, atTick: 0, in: docOn, bpm: 120)   // play #1
        p.apply(in: docMuted, fromTick: 100, toTick: 200, bpm: 120)                    // mute → stop
        XCTAssertEqual(factory.sinks.first?.stops, 1)
        // Unmute at tick 480 (0.5 s into the loop) → resume at that phase, not the top.
        p.apply(in: docOn, fromTick: 400, toTick: 480, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.plays.count, 2, "unmute resumes the launched clip")
        XCTAssertEqual(factory.sinks.first?.plays.last?.from ?? -1, 0.5, accuracy: 1e-6,
                       "resume lands at the honest loop phase, not the region top")
    }

    /// Muting the lane stops a launched clip (live mixer works on an override too).
    func testLaunchOverride_muteStopsLaunchedClip() {
        let lane = TimelineLane(name: "Audio 1", kind: .audio)
        let region = TimelineRegion(laneID: lane.id, clipID: UUID(),
                                    startTick: 0, lengthTicks: 1920)
        let docOn = TimelineDocument(lanes: [lane], regions: [region])
        var mutedLane = lane; mutedLane.isMuted = true
        let docMuted = TimelineDocument(lanes: [mutedLane], regions: [region])
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.setLaunchOverride(region, laneID: lane.id, atTick: 0, in: docOn, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.plays.count, 1)
        p.apply(in: docMuted, fromTick: 100, toTick: 200, bpm: 120)   // no wrap; gain → 0
        XCTAssertEqual(factory.sinks.first?.stops, 1, "mute silences the launched clip")
    }

    /// clearAll drops the override state (transport-reset path).
    func testClearAllLaunchOverrides_dropsState() {
        let (document, laneID) = doc()
        let region = document.regions[0]
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.setLaunchOverride(region, laneID: laneID, atTick: 0, in: document, bpm: 120)
        p.clearAllLaunchOverrides()
        XCTAssertFalse(p.hasLaunchOverrides)
        XCTAssertFalse(p.isLaunchOverriding(laneID))
    }

    /// Golden gate: with NO override, `apply` is the plain arrangement path — the
    /// launch branch is inert (empty override map).
    func testGoldenGate_noOverride_playsArrangementNormally() {
        let (document, laneID) = doc()
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        XCTAssertFalse(p.hasLaunchOverrides)
        XCTAssertFalse(p.isLaunchOverriding(laneID))
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)      // normal onset
        XCTAssertEqual(factory.sinks.first?.plays.count, 1, "arrangement onset unaffected")
    }

    // MARK: - S3: override lifecycle across re-prime, song-loop wrap, structure edits

    /// A re-prime (song-loop wrap / structure edit) must NOT restart the arrangement
    /// on a launched lane — the override keeps looping (mirrors MIDI primeSecondary).
    func testPrime_skipsOverriddenLane_noArrangementClobber() {
        let (document, laneID) = doc(length: 1920)
        let region = document.regions[0]
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.setLaunchOverride(region, laneID: laneID, atTick: 0, in: document, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.plays.count, 1)
        p.prime(in: document, atTick: 0, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.plays.count, 1,
                       "prime skips the launched lane — no arrangement clobber")
        XCTAssertTrue(p.isLaunchOverriding(laneID))
    }

    /// A song-loop wrap folds the override anchor by the loop length, so the loop
    /// keeps firing at the post-wrap boundary instead of a stale (negative-elapsed) one.
    func testShiftLaunchOverrides_foldsAnchor_soPostWrapLoopReTriggers() {
        let (document, laneID) = doc(length: 1920)
        let region = document.regions[0]
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.setLaunchOverride(region, laneID: laneID, atTick: 1920, in: document, bpm: 120)  // anchor @ bar 1
        XCTAssertEqual(factory.sinks.first?.plays.count, 1)
        p.shiftLaunchOverrides(by: -1920)   // transport wrapped: fold the anchor to 0
        XCTAssertTrue(p.isLaunchOverriding(laneID), "shift keeps the override")
        p.apply(in: document, fromTick: 1900, toTick: 1940, bpm: 120)   // crosses the tick-0-anchored bar
        XCTAssertEqual(factory.sinks.first?.plays.count, 2, "the folded anchor lets the loop wrap fire")
    }

    /// A structural edit that DELETES the launched region drops the override and stops
    /// its now-orphaned audio (no phantom-region loop).
    func testPruneLaunchOverrides_dropsDeletedRegion_andStops() {
        let (document, laneID) = doc(length: 1920)
        let region = document.regions[0]
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.setLaunchOverride(region, laneID: laneID, atTick: 0, in: document, bpm: 120)
        p.pruneLaunchOverrides(validLaneIDs: [laneID], validRegionIDs: [])   // region gone
        XCTAssertFalse(p.isLaunchOverriding(laneID))
        XCTAssertEqual(factory.sinks.first?.stops, 1, "the orphaned launched audio is stopped")
    }

    /// A still-valid launched region survives an unrelated structure edit's prune.
    func testPruneLaunchOverrides_keepsSurvivingOverride() {
        let (document, laneID) = doc(length: 1920)
        let region = document.regions[0]
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.setLaunchOverride(region, laneID: laneID, atTick: 0, in: document, bpm: 120)
        p.pruneLaunchOverrides(validLaneIDs: [laneID], validRegionIDs: [region.id])
        XCTAssertTrue(p.isLaunchOverriding(laneID), "a still-valid launched region survives prune")
        XCTAssertEqual(factory.sinks.first?.stops, 0)
    }

    /// A removed LANE drops its override too.
    func testPruneLaunchOverrides_dropsRemovedLane() {
        let (document, laneID) = doc(length: 1920)
        let region = document.regions[0]
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.setLaunchOverride(region, laneID: laneID, atTick: 0, in: document, bpm: 120)
        p.pruneLaunchOverrides(validLaneIDs: [], validRegionIDs: [region.id])   // lane gone
        XCTAssertFalse(p.isLaunchOverriding(laneID))
        XCTAssertFalse(p.hasLaunchOverrides)
    }
}
