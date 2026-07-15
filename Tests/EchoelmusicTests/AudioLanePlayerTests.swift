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
        }
        var plays: [Play] = []
        var stops = 0
        var preloads: [URL] = []
        var detaches = 0
        var gains: [Float] = []
        var pans: [Float] = []
        func play(url: URL, fromSeconds: Double, lengthSeconds: Double, gain: Float) {
            plays.append(Play(url: url, from: fromSeconds, length: lengthSeconds, gain: gain))
        }
        func stop() { stops += 1 }
        func preload(url: URL) { preloads.append(url) }
        func detach() { detaches += 1 }
        func setGain(_ gain: Float) { gains.append(gain) }
        func setPan(_ pan: Float) { pans.append(pan) }
    }

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

    private func player(_ factory: Factory, resolve: @escaping (UUID) -> URL?) -> AudioLanePlayer {
        AudioLanePlayer(makeSink: factory.make, resolveURL: resolve)
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

    func testPan_appliedAtOnset_andLiveEdit() {
        var (document, _) = doc()
        document.lanes[0].pan = 0.5
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.pans.last ?? -1, 0.5, accuracy: 1e-6, "pan set at onset")
        p.apply(in: edited(document, pan: -1), fromTick: 0, toTick: 480, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.pans.last ?? -1, -1, accuracy: 1e-6, "live pan edit lands")
        XCTAssertEqual(factory.sinks.first?.plays.count, 1, "pan never re-schedules")
    }
}
