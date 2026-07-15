// RegionNoteWindowTests.swift
// M1a of the clip-pro healing block (founder 2026-07-15, ultracode audit
// wf_9c6f33b7-6ff): the PURE windowing core that makes a MIDI region play exactly
// the notes its block covers — trim-in windowing (front-trim/split hide notes),
// region-end clipping (sustains stop at the block edge), and per-bar slices for
// the existing bar-cycling loadArrangement mechanic. Reference: ticksPerBar = 1920,
// ticksPerStep = 120; TimelineTime.ticks(fromSeconds: 0.5, bpm: 120) = 480.

import XCTest
@testable import Echoelmusic

final class RegionNoteWindowTests: XCTestCase {

    private func note(_ tick: Int, len: Int = 120, pitch: Int = 60) -> Note {
        Note(pitch: pitch, startTick: tick, lengthTicks: len)
    }

    // MARK: - windowed(notes:offsetTicks:lengthTicks:)

    func testWindow_keepsOnlyNotesStartingInside_rebased() {
        let notes = [note(0), note(1920, pitch: 62), note(3840, pitch: 64)]
        let w = RegionNoteWindow.windowed(notes: notes, offsetTicks: 0, lengthTicks: 1920)
        XCTAssertEqual(w.map(\.pitch), [60], "a one-bar window shows only bar-1 notes")
        XCTAssertEqual(w[0].startTick, 0)
    }

    func testWindow_frontTrim_dropsEarlierNotes_andRebases() {
        // Front-trim of one bar: the bar-2 note becomes the region's first note.
        let notes = [note(0), note(1920, pitch: 62), note(2040, pitch: 64)]
        let w = RegionNoteWindow.windowed(notes: notes, offsetTicks: 1920, lengthTicks: 1920)
        XCTAssertEqual(w.map(\.pitch), [62, 64], "trimmed-away notes must NOT sound")
        XCTAssertEqual(w[0].startTick, 0, "rebased to region-relative time")
        XCTAssertEqual(w[1].startTick, 120)
    }

    func testWindow_noteStartingBeforeOffset_isExcludedEvenIfSustaining() {
        // Pro-DAW trim: a note that STARTS before the region start does not sound,
        // even when its tail would reach into the region.
        let notes = [note(1800, len: 400, pitch: 60), note(1920, pitch: 62)]
        let w = RegionNoteWindow.windowed(notes: notes, offsetTicks: 1920, lengthTicks: 1920)
        XCTAssertEqual(w.map(\.pitch), [62])
    }

    func testWindow_clipsSustainAtRegionEnd() {
        // A note overhanging the region end is CLIPPED to the block edge.
        let notes = [note(1800, len: 400)]
        let w = RegionNoteWindow.windowed(notes: notes, offsetTicks: 0, lengthTicks: 1920)
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(w[0].startTick, 1800)
        XCTAssertEqual(w[0].lengthTicks, 120, "sustain stops at the region boundary")
    }

    func testWindow_degenerateLength_returnsEmpty() {
        XCTAssertTrue(RegionNoteWindow.windowed(notes: [note(0)], offsetTicks: 0,
                                                lengthTicks: 0).isEmpty)
        XCTAssertTrue(RegionNoteWindow.windowed(notes: [note(0)], offsetTicks: -120,
                                                lengthTicks: 1920).count == 1,
                      "a negative offset clamps to 0, not a crash")
    }

    // MARK: - barSlices(notes:regionLengthTicks:)

    func testBarSlices_twoBarRegion_slicesAndRebasesPerBar() {
        // Region-relative notes across two bars → 2 slices, each bar-relative.
        let notes = [note(0), note(480, pitch: 61), note(1920, pitch: 62), note(2040, pitch: 63)]
        let slices = RegionNoteWindow.barSlices(notes: notes, regionLengthTicks: 3840)
        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(slices[0].map(\.pitch), [60, 61])
        XCTAssertEqual(slices[1].map(\.pitch), [62, 63])
        XCTAssertEqual(slices[1][0].startTick, 0, "bar 2's first note rebased to bar-relative 0")
        XCTAssertEqual(slices[1][1].startTick, 120)
    }

    func testBarSlices_partialLastBar_stillGetsASlice() {
        // A 1.5-bar region = 2 slices (the half bar is a real playing bar).
        let notes = [note(0), note(2040, pitch: 62)]
        let slices = RegionNoteWindow.barSlices(notes: notes, regionLengthTicks: 2880)
        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(slices[1].map(\.pitch), [62])
    }

    func testBarSlices_emptyRegion_isOneEmptyBar() {
        let slices = RegionNoteWindow.barSlices(notes: [], regionLengthTicks: 1920)
        XCTAssertEqual(slices.count, 1)
        XCTAssertTrue(slices[0].isEmpty)
    }

    func testBarSlices_noteCrossingBarBoundary_staysInItsStartBar_uncut() {
        // A sustain across the bar line belongs to its START bar and keeps its
        // length (only the REGION end clips) — noteOff falls in the next bar.
        let notes = [note(1800, len: 400)]
        let slices = RegionNoteWindow.barSlices(notes: notes, regionLengthTicks: 3840)
        XCTAssertEqual(slices[0].count, 1)
        XCTAssertEqual(slices[0][0].lengthTicks, 400)
        XCTAssertTrue(slices[1].isEmpty)
    }

    func testBarSlices_noteInLastHalfStep_clampsOntoStep15_notDropped() {
        // Bar-relative tick 1880 would round to startStep 16 — a step the 0…15
        // trigger never fires. The slice clamps it onto the last real step instead.
        let notes = [note(1880)]
        let slices = RegionNoteWindow.barSlices(notes: notes, regionLengthTicks: 1920)
        XCTAssertEqual(slices[0].count, 1, "the note must not silently vanish")
        XCTAssertEqual(slices[0][0].startStep, 15)
    }

    // MARK: - stepAligned + tick-domain trim (tempo-proof)

    func testStepAligned_snapsToNearestStep() {
        XCTAssertEqual(RegionNoteWindow.stepAligned(0), 0)
        XCTAssertEqual(RegionNoteWindow.stepAligned(59), 0)
        XCTAssertEqual(RegionNoteWindow.stepAligned(60), 120)
        XCTAssertEqual(RegionNoteWindow.stepAligned(1919), 1920)
        XCTAssertEqual(RegionNoteWindow.stepAligned(-5), 0)
    }

    func testRegionSplit_maintainsTickOffset_exactAtAnyLaterTempo() {
        // Split at bar 1 @120 stores seconds AND ticks; the tick twin must be
        // exactly one bar regardless of what the tempo does afterwards (the
        // reviewer's HIGH: seconds re-converted at play-time tempo drift).
        let region = TimelineRegion(laneID: UUID(), clipID: UUID(),
                                    startTick: 0, lengthTicks: 3840)
        let pieces = region.split(at: 1920, bpm: 120)
        XCTAssertEqual(pieces?.1.contentOffsetTicks, 1920)
        // Chained edit at a DIFFERENT tempo stays in the tick domain.
        let trimmed = pieces?.1.trimmedStart(toTick: 2040, bpm: 93.7)
        XCTAssertEqual(trimmed?.contentOffsetTicks, 2040)
    }

    // MARK: - offsetTicks(contentOffsetSeconds:bpm:)

    func testOffsetTicks_convertsSecondsAtTempo() {
        XCTAssertEqual(RegionNoteWindow.offsetTicks(contentOffsetSeconds: 0.5, bpm: 120), 480)
        XCTAssertEqual(RegionNoteWindow.offsetTicks(contentOffsetSeconds: 0, bpm: 120), 0)
        XCTAssertEqual(RegionNoteWindow.offsetTicks(contentOffsetSeconds: -1, bpm: 120), 0,
                       "negative offsets clamp to 0")
        XCTAssertEqual(RegionNoteWindow.offsetTicks(contentOffsetSeconds: 1, bpm: 0), 0,
                       "degenerate bpm is safe")
    }

    // MARK: - ArrangementLoadPlan (region-relative bar cycling phase)

    func testPlan_stopped_loadsStartBar_offsetEqualsStartBar() {
        let p = ArrangementLoadPlan.plan(barCount: 4, startBar: 2, playedBars: 99,
                                         atStepZero: false, playing: false)
        XCTAssertEqual(p, ArrangementLoadPlan(nowIndex: 2, pendingIndex: nil, phaseOffset: 2),
                       "caller resets playedBars to 0, so offset = startBar")
    }

    func testPlan_playingAtStepZero_noStagedBar_andGlobalCounterRotated() {
        // Region onset ON the bar line at global bar 5 (playedBars == 5), region bar 0.
        // trigger(0) runs after the load in the SAME tick: it must find nothing staged,
        // then stages (playedBars+1 + offset) ≡ 1 — the region's bar 1.
        let p = ArrangementLoadPlan.plan(barCount: 3, startBar: 0, playedBars: 5,
                                         atStepZero: true, playing: true)
        XCTAssertEqual(p.nowIndex, 0)
        XCTAssertNil(p.pendingIndex, "staging here would be consumed this very tick")
        XCTAssertEqual((5 + 1 + p.phaseOffset) % 3, 1, "next bar line stages region bar 1")
    }

    func testPlan_playingMidBar_stagesNextBar_andOffsetSkewedByOne() {
        // Mid-bar onset in global bar 5: playedBars was ALREADY incremented to 6 at
        // this bar's own step 0. The NEXT trigger(0) first consumes the staged bar
        // (must be region bar 1), then stages (6+1 + offset) ≡ 2.
        let p = ArrangementLoadPlan.plan(barCount: 3, startBar: 0, playedBars: 6,
                                         atStepZero: false, playing: true)
        XCTAssertEqual(p.nowIndex, 0)
        XCTAssertEqual(p.pendingIndex, 1)
        XCTAssertEqual((6 + 1 + p.phaseOffset) % 3, 2, "bar after next stages region bar 2")
    }

    func testPlan_singleBar_neverStages() {
        let p = ArrangementLoadPlan.plan(barCount: 1, startBar: 0, playedBars: 7,
                                         atStepZero: false, playing: true)
        XCTAssertEqual(p.nowIndex, 0)
        XCTAssertNil(p.pendingIndex, "a 1-bar region has nothing to cycle")
    }

    func testPlan_startBarWrapsIntoRange() {
        let p = ArrangementLoadPlan.plan(barCount: 2, startBar: 5, playedBars: 0,
                                         atStepZero: true, playing: true)
        XCTAssertEqual(p.nowIndex, 1, "startBar is taken modulo the bar count")
    }

    // MARK: - The founder scenario, end to end (pure)

    func testSplitScenario_rightHalfPlaysBar2Content() {
        // A 2-bar clip split at bar 2: the RIGHT piece (offset = 1 bar) must play
        // the bar-2 notes at ITS bar 1 — not replay bar 1 (the audited defect).
        let clipNotes = [note(0, pitch: 60), note(1920, pitch: 72)]
        let rightOffset = RegionNoteWindow.offsetTicks(
            contentOffsetSeconds: TimelineTime.seconds(fromTicks: 1920, bpm: 120), bpm: 120)
        XCTAssertEqual(rightOffset, 1920)
        let right = RegionNoteWindow.windowed(notes: clipNotes,
                                              offsetTicks: rightOffset, lengthTicks: 1920)
        XCTAssertEqual(right.map(\.pitch), [72])
        XCTAssertEqual(right[0].startTick, 0)
        let slices = RegionNoteWindow.barSlices(notes: right, regionLengthTicks: 1920)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices[0].map(\.pitch), [72])
    }
}
