// LaneLaunchLatchTests.swift
// Echoel — lane-scoped launch core (P4): quantize boundaries, loop wrap, latch state
// machine (queued/latched/release/cancel/stop), and gesture→intent mapping. Pure —
// no engine, no audio → runs on every platform.

import XCTest
@testable import Echoelmusic

final class LaneLaunchLatchTests: XCTestCase {

    private let bar = TimelineTime.ticksPerBar        // 1920
    private let beat = TimelineTime.ticksPerBeat      // 480
    private func clip(_ len: Int = 1920) -> LaunchedClip {
        LaunchedClip(clipID: UUID(), loopLengthTicks: len)
    }

    // MARK: - nextLaunchTick

    func testNextLaunchTick_barGrid_snapsToNextBoundaryStrictlyAfter() {
        XCTAssertEqual(LaunchTiming.nextLaunchTick(now: 1,    quantize: .bar), bar)
        XCTAssertEqual(LaunchTiming.nextLaunchTick(now: 1900, quantize: .bar), bar)
        XCTAssertEqual(LaunchTiming.nextLaunchTick(now: bar,  quantize: .bar), bar * 2)   // on boundary → NEXT
        XCTAssertEqual(LaunchTiming.nextLaunchTick(now: 0,    quantize: .bar), bar)
    }

    func testNextLaunchTick_beatGrid() {
        XCTAssertEqual(LaunchTiming.nextLaunchTick(now: 1,   quantize: .beat), beat)
        XCTAssertEqual(LaunchTiming.nextLaunchTick(now: 500, quantize: .beat), beat * 2)
    }

    func testNextLaunchTick_off_isImmediate() {
        XCTAssertEqual(LaunchTiming.nextLaunchTick(now: 777, quantize: .off), 777)
    }

    func testAllGridsAreStepAligned() {
        for q in LaunchQuantize.allCases {
            if let t = q.ticks {
                XCTAssertEqual(t % TimelineTime.ticksPerTransportStep, 0, "\(q) not step-aligned")
            }
        }
    }

    // MARK: - crossed

    func testCrossed_halfOpenLeftClosedRight() {
        XCTAssertTrue(LaunchTiming.crossed(boundary: bar, from: bar - 120, to: bar))
        XCTAssertFalse(LaunchTiming.crossed(boundary: bar, from: bar, to: bar + 120))
        XCTAssertFalse(LaunchTiming.crossed(boundary: bar, from: 0, to: bar - 120))
    }

    // MARK: - loop math

    func testLoopContentTick_wrapsWithinClip() {
        XCTAssertEqual(LaunchTiming.loopContentTick(now: 0,         sinceTick: 0, loopLength: bar), 0)
        XCTAssertEqual(LaunchTiming.loopContentTick(now: 100,       sinceTick: 0, loopLength: bar), 100)
        XCTAssertEqual(LaunchTiming.loopContentTick(now: bar,       sinceTick: 0, loopLength: bar), 0)
        XCTAssertEqual(LaunchTiming.loopContentTick(now: bar + 240, sinceTick: 0, loopLength: bar), 240)
        XCTAssertEqual(LaunchTiming.loopContentTick(now: 10, sinceTick: 100, loopLength: bar), 0)
    }

    func testLoopWrapped_detectsBoundaryCrossing() {
        XCTAssertTrue(LaunchTiming.loopWrapped(from: bar - 60, to: bar + 60, sinceTick: 0, loopLength: bar))
        XCTAssertFalse(LaunchTiming.loopWrapped(from: 60, to: 120, sinceTick: 0, loopLength: bar))
        XCTAssertFalse(LaunchTiming.loopWrapped(from: 120, to: 120, sinceTick: 0, loopLength: bar))
    }

    // MARK: - latch: immediate

    func testRequestLaunch_whenStopped_latchesImmediately() {
        var l = LaneLaunchLatch()
        let c = clip()
        let e = l.requestLaunch(c, now: 500, quantize: .bar, isPlaying: false)
        XCTAssertEqual(e, .latch(c))
        XCTAssertTrue(l.isLatched)
        XCTAssertEqual(l.activeClipID, c.clipID)
        XCTAssertNil(l.pending)
    }

    func testRequestLaunch_offGrid_latchesImmediatelyEvenWhilePlaying() {
        var l = LaneLaunchLatch()
        let c = clip()
        XCTAssertEqual(l.requestLaunch(c, now: 500, quantize: .off, isPlaying: true), .latch(c))
        XCTAssertTrue(l.isLatched)
    }

    // MARK: - latch: quantized queue → fire

    func testRequestLaunch_whilePlaying_queuesUntilBoundary() {
        var l = LaneLaunchLatch()
        let c = clip()
        XCTAssertEqual(l.requestLaunch(c, now: 500, quantize: .bar, isPlaying: true), .none)
        XCTAssertEqual(l.pendingClipID, c.clipID)
        XCTAssertFalse(l.isLatched)

        XCTAssertEqual(l.resolve(from: 500, to: 620), .none)
        XCTAssertEqual(l.resolve(from: bar - 120, to: bar), .latch(c))
        XCTAssertTrue(l.isLatched)
        XCTAssertEqual(l.activeClipID, c.clipID)
        XCTAssertNil(l.pending)
    }

    // MARK: - latch: queued-then-cancel

    func testCancelPending_neverFires() {
        var l = LaneLaunchLatch()
        _ = l.requestLaunch(clip(), now: 100, quantize: .bar, isPlaying: true)
        XCTAssertNotNil(l.pending)
        l.cancelPending()
        XCTAssertNil(l.pending)
        XCTAssertEqual(l.resolve(from: bar - 120, to: bar), .none)
        XCTAssertFalse(l.isLatched)
    }

    // MARK: - latch: swap while latched

    func testRequestLaunch_whileLatched_queuesSwapKeepsOldUntilBoundary() {
        var l = LaneLaunchLatch()
        let a = clip(), b = clip()
        _ = l.requestLaunch(a, now: 0, quantize: .off, isPlaying: true)
        XCTAssertEqual(l.activeClipID, a.clipID)
        _ = l.requestLaunch(b, now: 100, quantize: .bar, isPlaying: true)
        XCTAssertEqual(l.activeClipID, a.clipID, "a still sounding")
        XCTAssertEqual(l.pendingClipID, b.clipID)
        XCTAssertEqual(l.resolve(from: bar - 120, to: bar), .latch(b))
        XCTAssertEqual(l.activeClipID, b.clipID)
    }

    // MARK: - release

    func testRequestStop_whilePlaying_queuesReleaseThenFollows() {
        var l = LaneLaunchLatch()
        _ = l.requestLaunch(clip(), now: 0, quantize: .off, isPlaying: true)
        XCTAssertEqual(l.requestStop(now: 100, quantize: .bar, isPlaying: true), .none)
        XCTAssertTrue(l.isReleasePending)
        XCTAssertEqual(l.resolve(from: bar - 120, to: bar), .release)
        XCTAssertFalse(l.isLatched)
    }

    func testRequestStop_whileFollowing_isNoOp() {
        var l = LaneLaunchLatch()
        XCTAssertEqual(l.requestStop(now: 0, quantize: .bar, isPlaying: true), .none)
        XCTAssertNil(l.pending)
    }

    func testHandleStop_clearsLatchAndPending() {
        var l = LaneLaunchLatch()
        _ = l.requestLaunch(clip(), now: 0, quantize: .off, isPlaying: true)
        _ = l.requestLaunch(clip(), now: 100, quantize: .bar, isPlaying: true)
        l.handleStop()
        XCTAssertFalse(l.isLatched)
        XCTAssertNil(l.pending)
    }

    // MARK: - latch loop position

    func testContentTick_isNilWhileFollowing_andLoopsWhileLatched() {
        var l = LaneLaunchLatch()
        XCTAssertNil(l.contentTick(at: 500))
        _ = l.requestLaunch(clip(bar), now: bar, quantize: .off, isPlaying: true)
        XCTAssertEqual(l.contentTick(at: bar), 0)
        XCTAssertEqual(l.contentTick(at: bar + 240), 240)
        XCTAssertEqual(l.contentTick(at: bar * 2), 0, "wraps at loop length")
        XCTAssertTrue(l.loopWrapped(from: bar * 2 - 60, to: bar * 2 + 60))
    }

    // MARK: - gesture → intent

    func testGesture_quickTapWideEnough_launches() {
        XCTAssertEqual(LaunchGestureResolver.resolve(
            elapsedSeconds: 0.1, movedPt: 2, released: true, renderedWidthPt: 40), .launch)
    }
    func testGesture_longPressRelease_opensEditor() {
        XCTAssertEqual(LaunchGestureResolver.resolve(
            elapsedSeconds: 0.5, movedPt: 2, released: true, renderedWidthPt: 40), .openEditor)
    }
    func testGesture_movePastSlop_isMove() {
        XCTAssertEqual(LaunchGestureResolver.resolve(
            elapsedSeconds: 0.5, movedPt: 30, released: false, renderedWidthPt: 40), .move)
    }
    func testGesture_notReleasedNoMove_isPending() {
        XCTAssertEqual(LaunchGestureResolver.resolve(
            elapsedSeconds: 0.1, movedPt: 1, released: false, renderedWidthPt: 40), .pending)
    }
    func testGesture_tapOnTooNarrowRegion_fallsBackToEditor() {
        XCTAssertEqual(LaunchGestureResolver.resolve(
            elapsedSeconds: 0.1, movedPt: 1, released: true, renderedWidthPt: 12), .openEditor)
    }
}
