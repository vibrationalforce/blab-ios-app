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

    // MARK: - offsetTicks(contentOffsetSeconds:bpm:)

    func testOffsetTicks_convertsSecondsAtTempo() {
        XCTAssertEqual(RegionNoteWindow.offsetTicks(contentOffsetSeconds: 0.5, bpm: 120), 480)
        XCTAssertEqual(RegionNoteWindow.offsetTicks(contentOffsetSeconds: 0, bpm: 120), 0)
        XCTAssertEqual(RegionNoteWindow.offsetTicks(contentOffsetSeconds: -1, bpm: 120), 0,
                       "negative offsets clamp to 0")
        XCTAssertEqual(RegionNoteWindow.offsetTicks(contentOffsetSeconds: 1, bpm: 0), 0,
                       "degenerate bpm is safe")
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
