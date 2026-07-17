// ClipLaunchEngineTests.swift
// Echoel — pure LAWS of the multi-lane clip-launch state machine (P0,
// PLAN_TIMELINE_AUTOMATION_PERFORMANCE). No clock, no audio, no @MainActor:
// ClipLaunchEngine is a Sendable value type, so every rule is unit-tested on
// Linux CI (Foundation-only). Mirrors LaneLaunchLatchTests in shape.
//
// Covered: boundaryTick math (on/before/after boundary, .off, negative→0),
// state transitions (idle→queued→playing at the boundary tick; requestStop
// quantized; double-launch no-op; a different region replaces the queue;
// launching the queued-stop region cancels the stop; launching the sounding
// region under a queued switch reverts it), loopedContentTick (elapsed≤0→0,
// modulo, length 0→0), shift, prune, tick ordering + at-most-one-per-lane,
// and isOverriding/soundingRegion per state.

import XCTest
@testable import Echoelmusic

final class ClipLaunchEngineTests: XCTestCase {

    private let bar = TimelineTime.ticksPerBar          // 1920
    private let beat = TimelineTime.ticksPerBeat        // 480
    private let lane = UUID()
    private let regionA = UUID()
    private let regionB = UUID()

    // MARK: - boundaryTick

    func testBoundaryTick_onBoundary_startsAtThatBoundary() {
        // A request already ON the boundary maps to itself — starts at that very
        // boundary, not a full grid later ("Tick AUF der Grenze startet sofort").
        XCTAssertEqual(ClipLaunchEngine.boundaryTick(onOrAfter: bar, quantize: .bar), bar)
        XCTAssertEqual(ClipLaunchEngine.boundaryTick(onOrAfter: 0, quantize: .bar), 0)
        XCTAssertEqual(ClipLaunchEngine.boundaryTick(onOrAfter: beat, quantize: .beat), beat)
    }

    func testBoundaryTick_beforeBoundary_snapsUpToNext() {
        XCTAssertEqual(ClipLaunchEngine.boundaryTick(onOrAfter: 1, quantize: .bar), bar)
        XCTAssertEqual(ClipLaunchEngine.boundaryTick(onOrAfter: bar - 1, quantize: .bar), bar)
        XCTAssertEqual(ClipLaunchEngine.boundaryTick(onOrAfter: 1, quantize: .beat), beat)
    }

    func testBoundaryTick_afterBoundary_snapsToTheFollowingGrid() {
        XCTAssertEqual(ClipLaunchEngine.boundaryTick(onOrAfter: bar + 1, quantize: .bar), bar * 2)
        XCTAssertEqual(ClipLaunchEngine.boundaryTick(onOrAfter: beat + 1, quantize: .beat), beat * 2)
    }

    func testBoundaryTick_off_returnsTickUnchanged() {
        XCTAssertEqual(ClipLaunchEngine.boundaryTick(onOrAfter: 777, quantize: .off), 777)
        XCTAssertEqual(ClipLaunchEngine.boundaryTick(onOrAfter: 0, quantize: .off), 0)
    }

    func testBoundaryTick_negative_clampsToZero() {
        XCTAssertEqual(ClipLaunchEngine.boundaryTick(onOrAfter: -50, quantize: .bar), 0)
        XCTAssertEqual(ClipLaunchEngine.boundaryTick(onOrAfter: -50, quantize: .off), 0)
    }

    // MARK: - loopedContentTick

    func testLoopedContentTick_beforeAnchor_clampsToZero() {
        XCTAssertEqual(ClipLaunchEngine.loopedContentTick(now: 100, startedAtTick: 200, lengthTicks: bar), 0)
        XCTAssertEqual(ClipLaunchEngine.loopedContentTick(now: 200, startedAtTick: 200, lengthTicks: bar), 0)
    }

    func testLoopedContentTick_foldsModuloLength() {
        XCTAssertEqual(ClipLaunchEngine.loopedContentTick(now: 200, startedAtTick: 0, lengthTicks: bar), 200)
        XCTAssertEqual(ClipLaunchEngine.loopedContentTick(now: bar + 5, startedAtTick: 0, lengthTicks: bar), 5)
        XCTAssertEqual(ClipLaunchEngine.loopedContentTick(now: bar * 3 + 7, startedAtTick: bar, lengthTicks: bar), 7)
    }

    func testLoopedContentTick_zeroLength_isZero() {
        XCTAssertEqual(ClipLaunchEngine.loopedContentTick(now: 500, startedAtTick: 0, lengthTicks: 0), 0)
        XCTAssertEqual(ClipLaunchEngine.loopedContentTick(now: 500, startedAtTick: 0, lengthTicks: -5), 0)
    }

    // MARK: - Empty / idle

    func testFreshEngine_isIdle_everyLaneIdle() {
        let e = ClipLaunchEngine()
        XCTAssertTrue(e.isIdle)
        XCTAssertEqual(e.state(laneID: lane), .idle)
        XCTAssertFalse(e.isOverriding(laneID: lane))
        XCTAssertNil(e.soundingRegion(laneID: lane))
        XCTAssertTrue(e.overriddenLaneIDs.isEmpty)
    }

    func testIdleEngine_tick_emitsNothing() {
        var e = ClipLaunchEngine()
        XCTAssertTrue(e.tick(now: 999_999).isEmpty)
        XCTAssertTrue(e.isIdle)
    }

    // MARK: - idle → queued → playing (the launch boundary)

    func testLaunchFromIdle_queuesUntilBoundary_thenStartsAtBoundaryTick() {
        var e = ClipLaunchEngine()
        e.requestLaunch(laneID: lane, regionID: regionA, atTick: 100, quantize: .bar)
        // Queued from idle: NOT overriding yet (arrangement keeps playing till the boundary).
        XCTAssertEqual(e.state(laneID: lane), .queued(regionID: regionA, startAtTick: bar, current: nil))
        XCTAssertFalse(e.isOverriding(laneID: lane))
        XCTAssertNil(e.soundingRegion(laneID: lane))

        // A tick BEFORE the boundary fires nothing and holds the queue.
        XCTAssertTrue(e.tick(now: bar - 1).isEmpty)
        XCTAssertFalse(e.isOverriding(laneID: lane))

        // The boundary tick fires .started anchored to the boundary; state → playing.
        let out = e.tick(now: bar)
        XCTAssertEqual(out, [LaunchTransition(laneID: lane, kind: .started(regionID: regionA), atTick: bar)])
        XCTAssertEqual(e.state(laneID: lane), .playing(LaunchedRegion(regionID: regionA, startedAtTick: bar)))
        XCTAssertTrue(e.isOverriding(laneID: lane))
        XCTAssertEqual(e.soundingRegion(laneID: lane), LaunchedRegion(regionID: regionA, startedAtTick: bar))
    }

    func testStart_anchorsToBoundary_evenWhenNowOvershoots() {
        var e = ClipLaunchEngine()
        e.requestLaunch(laneID: lane, regionID: regionA, atTick: 1, quantize: .bar)
        // Sampled now overshoots the boundary — the transition + loop anchor stay AT the boundary.
        let out = e.tick(now: bar + 200)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.atTick, bar)
        XCTAssertEqual(e.soundingRegion(laneID: lane)?.startedAtTick, bar)
    }

    func testLaunchOff_firesImmediatelyOnNextTick() {
        var e = ClipLaunchEngine()
        e.requestLaunch(laneID: lane, regionID: regionA, atTick: 500, quantize: .off)
        XCTAssertEqual(e.state(laneID: lane), .queued(regionID: regionA, startAtTick: 500, current: nil))
        let out = e.tick(now: 500)
        XCTAssertEqual(out, [LaunchTransition(laneID: lane, kind: .started(regionID: regionA), atTick: 500)])
        XCTAssertTrue(e.isOverriding(laneID: lane))
    }

    // MARK: - stop (quantized)

    func testStop_quantizesToBoundary_thenReturnsToArrangement() {
        var e = playing(regionA, startedAt: bar)   // already sounding
        e.requestStop(laneID: lane, atTick: bar + 1, quantize: .bar)
        XCTAssertEqual(e.state(laneID: lane), .queuedStop(current: LaunchedRegion(regionID: regionA, startedAtTick: bar),
                                                          stopAtTick: bar * 2))
        XCTAssertTrue(e.isOverriding(laneID: lane))   // keeps looping until the stop boundary

        XCTAssertTrue(e.tick(now: bar * 2 - 1).isEmpty)
        let out = e.tick(now: bar * 2)
        XCTAssertEqual(out, [LaunchTransition(laneID: lane, kind: .stopped(regionID: regionA), atTick: bar * 2)])
        XCTAssertEqual(e.state(laneID: lane), .idle)
        XCTAssertTrue(e.isIdle)
    }

    func testStop_reQuantizes_lastTapWins() {
        var e = playing(regionA, startedAt: 0)
        e.requestStop(laneID: lane, atTick: 1, quantize: .bar)
        e.requestStop(laneID: lane, atTick: bar + 1, quantize: .bar)   // re-tap later
        XCTAssertEqual(e.state(laneID: lane), .queuedStop(current: LaunchedRegion(regionID: regionA, startedAtTick: 0),
                                                          stopAtTick: bar * 2))
    }

    func testStop_whileQueuedFromIdle_simplyUnqueues() {
        var e = ClipLaunchEngine()
        e.requestLaunch(laneID: lane, regionID: regionA, atTick: 1, quantize: .bar)
        e.requestStop(laneID: lane, atTick: 1, quantize: .bar)   // never started → un-queue
        XCTAssertEqual(e.state(laneID: lane), .idle)
        XCTAssertTrue(e.isIdle)
    }

    func testStop_whileIdle_isNoOp() {
        var e = ClipLaunchEngine()
        e.requestStop(laneID: lane, atTick: 10, quantize: .bar)
        XCTAssertTrue(e.isIdle)
    }

    // MARK: - double-launch / replace / cancel laws

    func testDoubleLaunch_ofQueuedRegion_isNoOp() {
        var e = ClipLaunchEngine()
        e.requestLaunch(laneID: lane, regionID: regionA, atTick: 1, quantize: .bar)
        let before = e
        e.requestLaunch(laneID: lane, regionID: regionA, atTick: 500, quantize: .beat)
        XCTAssertEqual(e, before)   // untouched
    }

    func testDoubleLaunch_ofPlayingRegion_isNoOp() {
        var e = playing(regionA, startedAt: bar)
        let before = e
        e.requestLaunch(laneID: lane, regionID: regionA, atTick: bar + 1, quantize: .bar)
        XCTAssertEqual(e, before)
    }

    func testLaunchDifferentRegion_whilePlaying_queuesSwitch_thenSwitchesOnce() {
        var e = playing(regionA, startedAt: bar)
        e.requestLaunch(laneID: lane, regionID: regionB, atTick: bar + 1, quantize: .bar)
        let current = LaunchedRegion(regionID: regionA, startedAtTick: bar)
        XCTAssertEqual(e.state(laneID: lane), .queued(regionID: regionB, startAtTick: bar * 2, current: current))
        XCTAssertTrue(e.isOverriding(laneID: lane))                        // A still sounds
        XCTAssertEqual(e.soundingRegion(laneID: lane), current)            // A is what's audible

        let out = e.tick(now: bar * 2)
        XCTAssertEqual(out, [LaunchTransition(laneID: lane,
                                              kind: .switched(fromRegionID: regionA, toRegionID: regionB),
                                              atTick: bar * 2)])
        XCTAssertEqual(e.soundingRegion(laneID: lane), LaunchedRegion(regionID: regionB, startedAtTick: bar * 2))
    }

    func testLaunchDifferentRegion_whileQueuedFromIdle_replacesTheQueue() {
        var e = ClipLaunchEngine()
        e.requestLaunch(laneID: lane, regionID: regionA, atTick: 1, quantize: .bar)
        e.requestLaunch(laneID: lane, regionID: regionB, atTick: 1, quantize: .bar)
        XCTAssertEqual(e.state(laneID: lane), .queued(regionID: regionB, startAtTick: bar, current: nil))
    }

    func testLaunch_theQueuedStopRegion_cancelsTheStop() {
        var e = playing(regionA, startedAt: bar)
        e.requestStop(laneID: lane, atTick: bar + 1, quantize: .bar)
        e.requestLaunch(laneID: lane, regionID: regionA, atTick: bar + 1, quantize: .bar)   // re-launch same
        XCTAssertEqual(e.state(laneID: lane), .playing(LaunchedRegion(regionID: regionA, startedAtTick: bar)))
    }

    func testLaunch_theSoundingRegion_underAQueuedSwitch_revertsTheSwitch() {
        var e = playing(regionA, startedAt: bar)
        e.requestLaunch(laneID: lane, regionID: regionB, atTick: bar + 1, quantize: .bar)   // queue switch A→B
        e.requestLaunch(laneID: lane, regionID: regionA, atTick: bar + 1, quantize: .bar)   // re-tap A
        XCTAssertEqual(e.state(laneID: lane), .playing(LaunchedRegion(regionID: regionA, startedAtTick: bar)))
    }

    func testStop_whileQueuedSwitch_queuesTheSoundingClipsStop() {
        var e = playing(regionA, startedAt: bar)
        e.requestLaunch(laneID: lane, regionID: regionB, atTick: bar + 1, quantize: .bar)   // queue switch
        e.requestStop(laneID: lane, atTick: bar + 1, quantize: .bar)                         // cancel switch + stop A
        XCTAssertEqual(e.state(laneID: lane), .queuedStop(current: LaunchedRegion(regionID: regionA, startedAtTick: bar),
                                                          stopAtTick: bar * 2))
    }

    // MARK: - tick ordering + at most one transition per lane

    func testTick_emitsStableLaneOrder_atMostOnePerLane() {
        let l1 = UUID(), l2 = UUID()
        var e = ClipLaunchEngine()
        e.requestLaunch(laneID: l1, regionID: regionA, atTick: 1, quantize: .bar)
        e.requestLaunch(laneID: l2, regionID: regionB, atTick: 1, quantize: .bar)
        let out = e.tick(now: bar)
        XCTAssertEqual(out.count, 2)                                        // one transition per lane
        let expected = [l1, l2].sorted { $0.uuidString < $1.uuidString }
        XCTAssertEqual(out.map(\.laneID), expected)                        // stable uuidString order
        // Each lane appears exactly once.
        XCTAssertEqual(Set(out.map(\.laneID)).count, out.count)
    }

    func testTick_ripe_startAndStopOnDifferentLanes_bothFireOnce() {
        let l1 = UUID(), l2 = UUID()
        var e = ClipLaunchEngine()
        e.requestLaunch(laneID: l1, regionID: regionA, atTick: 1, quantize: .bar)   // → started
        // l2 already playing, queue its stop for the same boundary.
        e.requestLaunch(laneID: l2, regionID: regionB, atTick: 1, quantize: .off)
        _ = e.tick(now: 1)                                                          // l2 now playing
        e.requestStop(laneID: l2, atTick: 1, quantize: .bar)                        // stop at bar
        let out = e.tick(now: bar)
        XCTAssertEqual(out.count, 2)
        XCTAssertTrue(out.contains(LaunchTransition(laneID: l1, kind: .started(regionID: regionA), atTick: bar)))
        XCTAssertTrue(out.contains(LaunchTransition(laneID: l2, kind: .stopped(regionID: regionB), atTick: bar)))
    }

    // MARK: - shift (song-loop-wrap rebase)

    func testShift_movesEveryStoredTick() {
        var e = ClipLaunchEngine()
        e.requestLaunch(laneID: lane, regionID: regionA, atTick: 1, quantize: .bar)   // queued @ bar
        e.shift(by: -bar)
        XCTAssertEqual(e.state(laneID: lane), .queued(regionID: regionA, startAtTick: 0, current: nil))
    }

    func testShift_playing_movesAnchor_canGoNegative() {
        var e = playing(regionA, startedAt: bar)
        e.shift(by: -bar * 2)
        XCTAssertEqual(e.soundingRegion(laneID: lane)?.startedAtTick, -bar)   // continuous across the wrap
    }

    func testShift_byZero_isNoOp() {
        var e = playing(regionA, startedAt: bar)
        let before = e
        e.shift(by: 0)
        XCTAssertEqual(e, before)
    }

    func testShift_queuedStop_movesBothStopTickAndCurrentAnchor() {
        var e = playing(regionA, startedAt: bar)
        e.requestStop(laneID: lane, atTick: bar + 1, quantize: .bar)   // queuedStop current@bar, stop@2·bar
        e.shift(by: -bar)
        XCTAssertEqual(e.state(laneID: lane),
                       .queuedStop(current: LaunchedRegion(regionID: regionA, startedAtTick: 0),
                                   stopAtTick: bar))
    }

    // MARK: - prune (structural edit reconcile)

    func testPrune_deletedLane_collapsesToIdle() {
        var e = playing(regionA, startedAt: bar)
        e.prune(validLaneIDs: [], validRegionIDs: [regionA])
        XCTAssertTrue(e.isIdle)
    }

    func testPrune_deletedPlayingRegion_collapsesToIdle() {
        var e = playing(regionA, startedAt: bar)
        e.prune(validLaneIDs: [lane], validRegionIDs: [])   // region gone
        XCTAssertEqual(e.state(laneID: lane), .idle)
    }

    func testPrune_queuedSwitch_lostQueuedRegion_survivesToCurrentPlaying() {
        var e = playing(regionA, startedAt: bar)
        e.requestLaunch(laneID: lane, regionID: regionB, atTick: bar + 1, quantize: .bar)  // queued switch A→B
        e.prune(validLaneIDs: [lane], validRegionIDs: [regionA])                            // B deleted, A survives
        XCTAssertEqual(e.state(laneID: lane), .playing(LaunchedRegion(regionID: regionA, startedAtTick: bar)))
    }

    func testPrune_queuedSwitch_lostCurrent_keepsQueueFromIdle() {
        var e = playing(regionA, startedAt: bar)
        e.requestLaunch(laneID: lane, regionID: regionB, atTick: bar + 1, quantize: .bar)  // queued switch A→B
        e.prune(validLaneIDs: [lane], validRegionIDs: [regionB])                            // A (current) deleted
        XCTAssertEqual(e.state(laneID: lane), .queued(regionID: regionB, startAtTick: bar * 2, current: nil))
        XCTAssertFalse(e.isOverriding(laneID: lane))   // no current sounds now
    }

    func testPrune_bothRegionsGone_collapsesToIdle() {
        var e = playing(regionA, startedAt: bar)
        e.requestLaunch(laneID: lane, regionID: regionB, atTick: bar + 1, quantize: .bar)
        e.prune(validLaneIDs: [lane], validRegionIDs: [])
        XCTAssertEqual(e.state(laneID: lane), .idle)
    }

    func testPrune_queuedStop_deletedRegion_collapsesToIdle() {
        var e = playing(regionA, startedAt: bar)
        e.requestStop(laneID: lane, atTick: bar + 1, quantize: .bar)   // queuedStop on A
        e.prune(validLaneIDs: [lane], validRegionIDs: [])              // A deleted under the stop
        XCTAssertEqual(e.state(laneID: lane), .idle)
    }

    // MARK: - overriddenLaneIDs / soundingRegion per state

    func testOverriddenLaneIDs_sortedAndOnlyOverridingLanes() {
        let l1 = UUID(), l2 = UUID(), l3 = UUID()
        var e = ClipLaunchEngine()
        // l1 playing (overriding), l2 queued-from-idle (NOT overriding), l3 playing.
        e.requestLaunch(laneID: l1, regionID: regionA, atTick: 1, quantize: .off)
        e.requestLaunch(laneID: l3, regionID: regionB, atTick: 1, quantize: .off)
        _ = e.tick(now: 1)
        e.requestLaunch(laneID: l2, regionID: regionA, atTick: 1, quantize: .bar)   // stays queued
        let expected = [l1, l3].sorted { $0.uuidString < $1.uuidString }
        XCTAssertEqual(e.overriddenLaneIDs, expected)
    }

    func testRemoveAll_dropsEveryLane() {
        var e = playing(regionA, startedAt: bar)
        e.requestLaunch(laneID: UUID(), regionID: regionB, atTick: 1, quantize: .bar)
        e.removeAll()
        XCTAssertTrue(e.isIdle)
    }

    func testClear_forcesOneLaneIdle_withoutTransition() {
        var e = playing(regionA, startedAt: bar)
        e.clear(laneID: lane)
        XCTAssertEqual(e.state(laneID: lane), .idle)
        XCTAssertTrue(e.isIdle)
    }

    // MARK: - Helpers

    /// An engine with `lane` already PLAYING `region` (anchored at `startedAt`).
    private func playing(_ region: UUID, startedAt: Int) -> ClipLaunchEngine {
        var e = ClipLaunchEngine()
        e.requestLaunch(laneID: lane, regionID: region, atTick: startedAt, quantize: .off)
        _ = e.tick(now: startedAt)
        XCTAssertEqual(e.state(laneID: lane), .playing(LaunchedRegion(regionID: region, startedAtTick: startedAt)))
        return e
    }
}
