// VideoLanePlayerTests.swift
// The transport-driven VIDEO-lane executor's logic, tested via a spy sink (no
// AVFoundation). Pins: active region → present at the right source-seconds; media
// shorter than the span → present held (playing:false); gap → stop; muted/
// unresolvable → stop. Reference: TimelineTime.seconds(fromTicks: 480, bpm: 120) = 0.5 s.

import XCTest
@testable import Echoelmusic

@MainActor
final class VideoLanePlayerTests: XCTestCase {

    final class SpySink: VideoRegionSink {
        struct Present: Equatable { let url: URL; let source: Double; let playing: Bool }
        var presents: [Present] = []
        var stops = 0
        func present(url: URL, atSourceSeconds sourceSeconds: Double, playing: Bool) {
            presents.append(Present(url: url, source: sourceSeconds, playing: playing))
        }
        func stop() { stops += 1 }
    }

    final class Factory {
        var sinks: [SpySink] = []
        func make() -> VideoRegionSink { let s = SpySink(); sinks.append(s); return s }
    }

    private let fileURL = URL(fileURLWithPath: "/tmp/echoel-test.mov")

    private func doc(start: Int = 0, length: Int = 1920, offset: Double = 0,
                     muted: Bool = false) -> (TimelineDocument, UUID) {
        let lane = TimelineLane(name: "Video 1", kind: .video, isMuted: muted)
        let region = TimelineRegion(laneID: lane.id, clipID: UUID(), startTick: start,
                                    lengthTicks: length, contentOffsetSeconds: offset)
        return (TimelineDocument(lanes: [lane], regions: [region]), lane.id)
    }

    private func player(_ factory: Factory, duration: Double = 3600,
                        resolve: @escaping (UUID) -> URL?) -> VideoLanePlayer {
        VideoLanePlayer(makeSink: factory.make, resolveURL: resolve, nativeDuration: { _ in duration })
    }

    // MARK: - Active → present

    func testActiveRegion_presentsAtSourceSeconds_playing() {
        let (document, _) = doc(offset: 2.0)
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        // 480 ticks (0.5 s @120) into the region, trim-in 2.0 → source 2.5.
        p.apply(in: document, atTick: 480, bpm: 120)
        XCTAssertEqual(factory.sinks.count, 1)
        let present = try? XCTUnwrap(factory.sinks.first?.presents.first)
        XCTAssertEqual(present?.url, fileURL)
        XCTAssertEqual(present?.source ?? -1, 2.5, accuracy: 1e-9, "trim-in + elapsed")
        XCTAssertEqual(present?.playing, true)
    }

    func testMediaShorterThanSpan_presentsHeldFrame() {
        // Native duration 1.0 s, but the playhead is 0.5 s into a bar-long region with
        // no trim-in → source 0.5 < 1.0 would be .play; push past the media instead.
        let (document, _) = doc(offset: 0)
        let factory = Factory()
        // duration 0.4 s: at tick 480 (0.5 s in) the source (0.5) exceeds it → exhausted.
        let p = player(factory, duration: 0.4) { _ in self.fileURL }
        p.apply(in: document, atTick: 480, bpm: 120)
        let present = try? XCTUnwrap(factory.sinks.first?.presents.first)
        XCTAssertEqual(present?.playing, false, "media ran out → hold the last frame")
    }

    // MARK: - Gap / gating

    func testGap_stops() {
        let (document, _) = doc()
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, atTick: 480, bpm: 120)      // active → creates sink + presents
        XCTAssertEqual(factory.sinks.first?.presents.count, 1)
        p.apply(in: document, atTick: 5000, bpm: 120)     // past the region → gap
        XCTAssertEqual(factory.sinks.first?.stops, 1, "leaving the region stops the lane")
    }

    func testMutedLane_neverPresents() {
        let (document, _) = doc(muted: true)
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, atTick: 480, bpm: 120)
        XCTAssertTrue(factory.sinks.isEmpty, "a muted video lane never reaches the present path")
    }

    func testUnresolvableFile_neverPresents() {
        let (document, _) = doc()
        let factory = Factory()
        let p = player(factory) { _ in nil }
        p.apply(in: document, atTick: 480, bpm: 120)
        XCTAssertTrue(factory.sinks.first?.presents.isEmpty ?? true, "no file ⇒ nothing shown")
    }

    /// A lane removed since the last apply must have its sink released (no stuck frame).
    func testRemovedLane_reconcileStopsItsSink() {
        let (document, _) = doc()
        let factory = Factory()
        let p = player(factory) { _ in self.fileURL }
        p.apply(in: document, atTick: 480, bpm: 120)                 // active → sink presents
        XCTAssertEqual(factory.sinks.first?.presents.count, 1)
        // Re-apply with a document that no longer has the video lane.
        p.apply(in: TimelineDocument(), atTick: 480, bpm: 120)
        XCTAssertEqual(factory.sinks.first?.stops, 1, "the removed lane's sink is stopped + released")
    }
}
