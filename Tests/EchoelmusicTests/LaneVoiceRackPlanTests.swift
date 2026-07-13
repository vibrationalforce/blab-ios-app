// LaneVoiceRackPlanTests.swift
// Pure tests for the fixed-N-voice rack reducer (LaneVoiceRackPlan).
// Deterministic: all UUIDs are fixed; no Date/random.

import XCTest
@testable import Echoelmusic

final class LaneVoiceRackPlanTests: XCTestCase {

    // MARK: - Fixtures

    private func laneID(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", n))")!
    }
    private func clipID(_ n: Int) -> UUID {
        UUID(uuidString: "11111111-1111-1111-1111-1111111111\(String(format: "%02d", n))")!
    }

    /// A `.load` step for lane `n` loading clip `n`. `slot` is intentionally passed as
    /// a "wrong" advisory value to prove the reducer ignores it (rank-based slotting).
    private func loadStep(_ n: Int) -> LanePlaybackStep {
        let region = TimelineRegion(laneID: laneID(n), clipID: clipID(n),
                                    startTick: 0, lengthTicks: 480)
        return LanePlaybackStep(laneID: laneID(n), event: .load(region), slot: nil)
    }
    private func clearStep(_ n: Int) -> LanePlaybackStep {
        LanePlaybackStep(laneID: laneID(n), event: .clear, slot: 999)
    }
    private func unchangedStep(_ n: Int) -> LanePlaybackStep {
        LanePlaybackStep(laneID: laneID(n), event: .unchanged, slot: 42)
    }

    // MARK: - Basic mapping

    func testEmptySteps_returnsEmpty() {
        XCTAssertEqual(LaneVoiceRackPlan.commands(steps: [], capacity: 4), [])
    }

    func testLoad_mapsToRankSlotWithClip() {
        let cmds = LaneVoiceRackPlan.commands(steps: [loadStep(1)], capacity: 4)
        XCTAssertEqual(cmds, [.load(slot: 0, clipID: clipID(1))])
    }

    func testClear_mapsToRankSlot() {
        let cmds = LaneVoiceRackPlan.commands(steps: [clearStep(1)], capacity: 4)
        XCTAssertEqual(cmds, [.clear(slot: 0)])
    }

    func testUnchanged_emitsNoCommand() {
        let cmds = LaneVoiceRackPlan.commands(steps: [unchangedStep(1)], capacity: 4)
        XCTAssertEqual(cmds, [])
    }

    func testMixedEvents_slotIsPriorityRank_notStepSlot() {
        // Ranks: 0 load, 1 unchanged (skipped), 2 clear.
        let cmds = LaneVoiceRackPlan.commands(
            steps: [loadStep(1), unchangedStep(2), clearStep(3)], capacity: 4)
        XCTAssertEqual(cmds, [
            .load(slot: 0, clipID: clipID(1)),
            .clear(slot: 2),
        ])
    }

    // MARK: - Deterministic slot assignment across churn

    func testChurn_addRemoveReadd_slotsAreRankStableAndDeterministic() {
        // Three lanes loading → slots 0,1,2.
        let three = LaneVoiceRackPlan.commands(
            steps: [loadStep(1), loadStep(2), loadStep(3)], capacity: 4)
        XCTAssertEqual(three, [
            .load(slot: 0, clipID: clipID(1)),
            .load(slot: 1, clipID: clipID(2)),
            .load(slot: 2, clipID: clipID(3)),
        ])

        // Remove the middle lane → remaining lanes re-rank to 0,1 deterministically.
        let removed = LaneVoiceRackPlan.commands(
            steps: [loadStep(1), loadStep(3)], capacity: 4)
        XCTAssertEqual(removed, [
            .load(slot: 0, clipID: clipID(1)),
            .load(slot: 1, clipID: clipID(3)),
        ])

        // Re-add it back in the original order → back to 0,1,2 exactly.
        let readded = LaneVoiceRackPlan.commands(
            steps: [loadStep(1), loadStep(2), loadStep(3)], capacity: 4)
        XCTAssertEqual(readded, three)
    }

    func testChurn_reType_clearThenLoadAtSameRank() {
        // A lane re-typed mid-song: its event flips clear→load but its rank (position)
        // is unchanged, so it stays on the same physical slot deterministically.
        let asClear = LaneVoiceRackPlan.commands(
            steps: [loadStep(1), clearStep(2)], capacity: 4)
        XCTAssertEqual(asClear, [
            .load(slot: 0, clipID: clipID(1)),
            .clear(slot: 1),
        ])
        let asLoad = LaneVoiceRackPlan.commands(
            steps: [loadStep(1), loadStep(2)], capacity: 4)
        XCTAssertEqual(asLoad, [
            .load(slot: 0, clipID: clipID(1)),
            .load(slot: 1, clipID: clipID(2)),
        ])
    }

    func testDeterminism_identicalInputYieldsIdenticalOutput() {
        let steps = [loadStep(1), clearStep(2), loadStep(3)]
        let a = LaneVoiceRackPlan.commands(steps: steps, capacity: 4)
        let b = LaneVoiceRackPlan.commands(steps: steps, capacity: 4)
        XCTAssertEqual(a, b)
    }

    // MARK: - Loop wrap

    func testLoopWrap_reloadEventsEmitLoadCommands() {
        // On a loop wrap the scheduler re-emits `.load` for each lane's first region;
        // every top lane must reload its own slot with its own clip.
        let cmds = LaneVoiceRackPlan.commands(
            steps: [loadStep(1), loadStep(2)], capacity: 4)
        XCTAssertEqual(cmds, [
            .load(slot: 0, clipID: clipID(1)),
            .load(slot: 1, clipID: clipID(2)),
        ])
    }

    // MARK: - Overflow ordering

    func testOverflow_topLanesKeepSlots_restSilencedInRankOrder() {
        // 4 loading lanes, capacity 2 → ranks 0,1 load; ranks 2,3 silence (ascending).
        let cmds = LaneVoiceRackPlan.commands(
            steps: [loadStep(1), loadStep(2), loadStep(3), loadStep(4)], capacity: 2)
        XCTAssertEqual(cmds, [
            .load(slot: 0, clipID: clipID(1)),
            .load(slot: 1, clipID: clipID(2)),
            .silence(slot: 2),
            .silence(slot: 3),
        ])
    }

    func testOverflow_silenceWinsOverEventForRanksBeyondCapacity() {
        // Even a lane whose event is .clear or .unchanged is silenced past capacity.
        let cmds = LaneVoiceRackPlan.commands(
            steps: [loadStep(1), clearStep(2), unchangedStep(3)], capacity: 1)
        XCTAssertEqual(cmds, [
            .load(slot: 0, clipID: clipID(1)),
            .silence(slot: 1),
            .silence(slot: 2),
        ])
    }

    func testExactlyAtCapacity_noSilence() {
        let cmds = LaneVoiceRackPlan.commands(
            steps: [loadStep(1), loadStep(2)], capacity: 2)
        XCTAssertEqual(cmds, [
            .load(slot: 0, clipID: clipID(1)),
            .load(slot: 1, clipID: clipID(2)),
        ])
    }

    // MARK: - Zero / negative capacity guards

    func testZeroCapacity_everyLaneSilenced() {
        let cmds = LaneVoiceRackPlan.commands(
            steps: [loadStep(1), loadStep(2)], capacity: 0)
        XCTAssertEqual(cmds, [.silence(slot: 0), .silence(slot: 1)])
    }

    func testNegativeCapacity_clampedToZero_everyLaneSilenced() {
        let cmds = LaneVoiceRackPlan.commands(
            steps: [loadStep(1), loadStep(2)], capacity: -5)
        XCTAssertEqual(cmds, [.silence(slot: 0), .silence(slot: 1)])
    }

    func testZeroCapacity_emptySteps_returnsEmpty() {
        XCTAssertEqual(LaneVoiceRackPlan.commands(steps: [], capacity: 0), [])
    }
}
