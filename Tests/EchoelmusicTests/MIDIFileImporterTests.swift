// MIDIFileImporterTests.swift
// Echoelmusic — Standard MIDI File → Note import (inverse of the exporter).

import XCTest
@testable import Echoelmusic

final class MIDIFileImporterTests: XCTestCase {

    func testRejectsNonMIDI() {
        XCTAssertThrowsError(try MIDIFileImporter.notes(from: [0x00, 0x01, 0x02, 0x03]))
    }

    func testRoundTripFromExporter() throws {
        // Export a melody, then re-import it and check pitches + ordering survive.
        let notes = [
            Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 0.8),
            Note(pitch: 64, startStep: 4, lengthSteps: 2, velocity: 0.6),
            Note(pitch: 67, startStep: 8, lengthSteps: 4, velocity: 1.0)
        ]
        let data = MIDIFileExporter.export(notes: notes, tempo: 120, humanize: .tight)
        let back = try MIDIFileImporter.notes(from: data)

        XCTAssertEqual(back.count, 3)
        XCTAssertEqual(back.map(\.pitch), [60, 64, 67], "pitches preserved, sorted by start")
        // Start steps survive the PPQ round-trip (exporter 96 PPQ → importer maps to 480).
        XCTAssertEqual(back.map(\.startStep), [0, 4, 8])
        // Durations are preserved (within a step of rounding).
        XCTAssertEqual(back[0].lengthSteps, 4)
        XCTAssertEqual(back[1].lengthSteps, 2)
    }

    func testVelocityPreservedApproximately() throws {
        let notes = [Note(pitch: 60, startStep: 0, lengthSteps: 2, velocity: 1.0)]
        let data = MIDIFileExporter.export(notes: notes, tempo: 120, humanize: .tight)
        let back = try MIDIFileImporter.notes(from: data)
        XCTAssertEqual(back.first?.velocity ?? 0, 1.0, accuracy: 0.02)
    }

    func testExcludesChannel10ByDefault() throws {
        // The combined exporter puts drums on channel 10; melody on channel 1.
        let melody = [Note(pitch: 62, startStep: 0, lengthSteps: 2, velocity: 0.7)]
        var grid = [[Bool]](repeating: [Bool](repeating: false, count: 16), count: 8)
        grid[0][0] = true; grid[0][8] = true     // kick hits → channel 10
        let data = MIDIFileExporter.exportCombined(notes: melody, steps: grid, tempo: 120)

        let melodyOnly = try MIDIFileImporter.notes(from: data)
        XCTAssertEqual(melodyOnly.map(\.pitch), [62], "drums on ch10 excluded by default")

        let withDrums = try MIDIFileImporter.notes(from: data, includeChannel10: true)
        XCTAssertGreaterThan(withDrums.count, melodyOnly.count, "ch10 included on request")
    }

    func testEmptyTakeImportsNoNotes() throws {
        let data = MIDIFileExporter.export(notes: [], tempo: 120)
        XCTAssertTrue(try MIDIFileImporter.notes(from: data).isEmpty)
    }

    // MARK: - DAW-usable N-bar loop export

    /// A saved 8/16-bar loop must export as N bars, not 1 — the founder's core requirement.
    /// A 4-bar melody with one note per bar must round-trip to its absolute bar positions.
    func testCombined_NBarRegion_keepsAbsoluteBarPositions() throws {
        let melody = [
            Note(pitch: 60, startStep: 0,  lengthSteps: 2),
            Note(pitch: 62, startStep: 16, lengthSteps: 2),   // bar 2
            Note(pitch: 64, startStep: 32, lengthSteps: 2),   // bar 3
            Note(pitch: 67, startStep: 48, lengthSteps: 2)    // bar 4
        ]
        let grid = [[Bool]](repeating: [Bool](repeating: false, count: 16), count: 8)
        let data = MIDIFileExporter.exportCombined(notes: melody, steps: grid, tempo: 120, bars: 4)
        let back = try MIDIFileImporter.notes(from: data)
        XCTAssertEqual(back.map(\.startStep), [0, 16, 32, 48],
                       "notes keep their bar positions across a 4-bar region")
    }

    /// The exported file carries a key-signature meta (FF 59 02 sf mi) so the DAW shows the
    /// Tonart. D minor → relative major F (1 flat) → sf = -1 (0xFF), mi = 1.
    func testCombined_writesKeySignatureMeta() {
        let data = MIDIFileExporter.exportCombined(
            notes: [Note(pitch: 62, startStep: 0)], steps: [], tempo: 120, bars: 1,
            keyRootPitchClass: 2, keyIsMinor: true)
        XCTAssertNotNil(subsequenceIndex([0xFF, 0x59, 0x02, 0xFF, 0x01], in: [UInt8](data)),
                        "D-minor key signature meta present")
    }

    /// C major → 0 sharps/flats, mi = 0.
    func testCombined_keySignature_CMajor() {
        let data = MIDIFileExporter.exportCombined(
            notes: [Note(pitch: 60, startStep: 0)], steps: [], tempo: 120, bars: 1,
            keyRootPitchClass: 0, keyIsMinor: false)
        XCTAssertNotNil(subsequenceIndex([0xFF, 0x59, 0x02, 0x00, 0x00], in: [UInt8](data)),
                        "C-major key signature meta present")
    }

    /// A 4/4 time-signature meta (FF 58 04 04 02 18 08) anchors the DAW grid.
    func testCombined_writesTimeSignatureMeta() {
        let data = MIDIFileExporter.exportCombined(
            notes: [Note(pitch: 60, startStep: 0)], steps: [], tempo: 120, bars: 2)
        XCTAssertNotNil(subsequenceIndex([0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08], in: [UInt8](data)),
                        "4/4 time signature meta present")
    }

    /// Find `needle` as a contiguous subsequence of `haystack` (nil if absent).
    private func subsequenceIndex(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for i in 0...(haystack.count - needle.count) where Array(haystack[i..<i + needle.count]) == needle {
            return i
        }
        return nil
    }

    // MARK: - Drum grid (GM channel 10 → BeatPlayer grid)

    func testDrumTrackMapping() {
        XCTAssertEqual(MIDIFileImporter.drumTrack(forGM: 36), 0, "bass drum → Kick")
        XCTAssertEqual(MIDIFileImporter.drumTrack(forGM: 38), 1, "snare → Snare")
        XCTAssertEqual(MIDIFileImporter.drumTrack(forGM: 42), 2, "closed hat → ClosedHat")
        XCTAssertEqual(MIDIFileImporter.drumTrack(forGM: 46), 3, "open hat → OpenHat")
        XCTAssertEqual(MIDIFileImporter.drumTrack(forGM: 39), 4, "hand clap → Clap")
        XCTAssertEqual(MIDIFileImporter.drumTrack(forGM: 51), 5, "ride → Perc (catch-all)")
    }

    func testDrumGridFromCombinedExport() throws {
        // Combined export puts kicks on ch10; build the grid back from it.
        var grid = [[Bool]](repeating: [Bool](repeating: false, count: 16), count: 8)
        grid[0][0] = true; grid[0][8] = true     // kick hits
        let data = MIDIFileExporter.exportCombined(notes: [], steps: grid, tempo: 120)

        let drums = try MIDIFileImporter.drumGrid(from: data)
        XCTAssertTrue(drums.steps[0][0], "kick at step 0 recovered")
        XCTAssertTrue(drums.steps[0][8], "kick at step 8 recovered")
        XCTAssertFalse(drums.steps[1].contains(true), "no snare hits")
    }

    func testDrumGridEmptyWhenNoPercussion() throws {
        let melodyOnly = MIDIFileExporter.export(notes: [Note(pitch: 60, startStep: 0)], tempo: 120)
        let drums = try MIDIFileImporter.drumGrid(from: melodyOnly)
        XCTAssertFalse(drums.steps.contains { $0.contains(true) }, "melody-only file → empty drum grid")
    }

    // MARK: - Fold-onto-grid (the piano-roll import adapter)

    @MainActor
    func testFoldToBar_dropsNotesPastTheFirstBar() {
        let inBar = Note(pitch: 60, startStep: 0, lengthSteps: 2)
        let nextBar = Note(pitch: 62, startStep: PianoRollModel.stepCount, lengthSteps: 2)
        let folded = PianoRollModel.foldToBar([inBar, nextBar])
        XCTAssertEqual(folded.map(\.pitch), [60], "only the first bar survives")
    }

    @MainActor
    func testFoldToBar_octaveFoldsPitchIntoVisibleRange() {
        let tooLow = Note(pitch: PianoRollModel.lowPitch - 24, startStep: 0)
        let tooHigh = Note(pitch: PianoRollModel.highPitch + 13, startStep: 1)
        let folded = PianoRollModel.foldToBar([tooLow, tooHigh])
        XCTAssertEqual(folded.count, 2)
        for n in folded {
            XCTAssertGreaterThanOrEqual(n.pitch, PianoRollModel.lowPitch)
            XCTAssertLessThanOrEqual(n.pitch, PianoRollModel.highPitch)
        }
        // Pitch classes are preserved by the octave fold.
        XCTAssertEqual(folded[0].pitch % 12, (PianoRollModel.lowPitch - 24 + 1200) % 12)
    }

    @MainActor
    func testFoldToBar_clampsLengthInsideTheBar() {
        let n = Note(pitch: 64, startStep: PianoRollModel.stepCount - 2, lengthSteps: 99)
        let folded = PianoRollModel.foldToBar([n])
        XCTAssertEqual(folded.first?.lengthSteps, 2, "length clamped so it never crosses the bar")
    }
}
