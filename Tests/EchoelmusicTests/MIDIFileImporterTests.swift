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
}
