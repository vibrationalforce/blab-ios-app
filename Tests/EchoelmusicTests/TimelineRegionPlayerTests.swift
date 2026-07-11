// TimelineRegionPlayerTests.swift
// Echoel — the PURE parts of timeline playback (reorg P3): the absolute-position
// cursor and the whole-bar loop-length math. The audio side (loadClip) mirrors the
// proven ArrangementPlayer and is verified on device; here we lock the position
// contract the scheduler rides on.

import XCTest
@testable import Echoelmusic

final class TimelineRegionPlayerTests: XCTestCase {

    // MARK: - TimelinePlaybackCursor (absolute position from within-bar steps)

    func testCursor_firstBar_ticksPerStep() {
        var c = TimelinePlaybackCursor()
        for s in 0..<16 {
            XCTAssertEqual(c.advance(step: s), s * 120, "step \(s) → tick \(s*120)")
        }
    }

    func testCursor_barWrap_advancesToNextBar() {
        var c = TimelinePlaybackCursor()
        for s in 0..<16 { _ = c.advance(step: s) }   // through bar 0 (…→1800)
        XCTAssertEqual(c.advance(step: 0), 1920, "15→0 wrap enters bar 1 (tick 1920)")
        XCTAssertEqual(c.advance(step: 1), 2040)
    }

    func testCursor_multipleBars() {
        var c = TimelinePlaybackCursor()
        for _ in 0..<3 {                              // three full bars
            for s in 0..<16 { _ = c.advance(step: s) }
        }
        XCTAssertEqual(c.advance(step: 0), 5760, "start of bar 3 = 3*1920")
    }

    func testCursor_noSpuriousWrapOnRepeatedStepZero() {
        var c = TimelinePlaybackCursor()
        XCTAssertEqual(c.advance(step: 0), 0, "first step 0 does not count as a wrap")
        XCTAssertEqual(c.advance(step: 0), 0, "a repeated step 0 (no 15→0) does not advance the bar")
    }

    func testCursor_clampsOutOfRangeSteps() {
        var c = TimelinePlaybackCursor()
        XCTAssertEqual(c.advance(step: -5), 0, "negative clamps to 0")
        XCTAssertEqual(c.advance(step: 99), 15 * 120, "over-15 clamps to 15")
    }

    // MARK: - loopTicks (whole-bar song length)

    private func doc(endTick: Int) -> TimelineDocument {
        let lane = TimelineLane(name: "MIDI", kind: .midi)
        // A single region [0, endTick) on the lane sets the document's endTick.
        let r = TimelineRegion(laneID: lane.id, clipID: UUID(), startTick: 0, lengthTicks: max(1, endTick))
        return TimelineDocument(lanes: [lane], regions: [r])
    }

    func testLoopTicks_exactBar_staysOneBar() {
        XCTAssertEqual(TimelineRegionPlayer.loopTicks(for: doc(endTick: 1920)), 1920)
    }

    func testLoopTicks_roundsUpToWholeBars() {
        XCTAssertEqual(TimelineRegionPlayer.loopTicks(for: doc(endTick: 1921)), 3840, "1 tick over one bar → two bars")
        XCTAssertEqual(TimelineRegionPlayer.loopTicks(for: doc(endTick: 2400)), 3840)
        XCTAssertEqual(TimelineRegionPlayer.loopTicks(for: doc(endTick: 3840)), 3840)
    }

    func testLoopTicks_emptySong_isZero() {
        XCTAssertEqual(TimelineRegionPlayer.loopTicks(for: TimelineDocument()), 0)
    }
}
