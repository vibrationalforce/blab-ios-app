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
        func play(url: URL, fromSeconds: Double, lengthSeconds: Double, gain: Float) {
            plays.append(Play(url: url, from: fromSeconds, length: lengthSeconds, gain: gain))
        }
        func stop() { stops += 1 }
        func preload(url: URL) { preloads.append(url) }
        func detach() { detaches += 1 }
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

    func testRemovedLane_reconcileDetachesItsSink() {
        let (document, _) = doc()
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, fromTick: -1, toTick: 0, bpm: 120)     // creates + plays
        p.apply(in: TimelineDocument(), fromTick: 0, toTick: 480, bpm: 120)   // lane gone
        XCTAssertEqual(factory.sinks.first?.stops, 1)
        XCTAssertEqual(factory.sinks.first?.detaches, 1, "the engine node is released, not just stopped")
    }
}
