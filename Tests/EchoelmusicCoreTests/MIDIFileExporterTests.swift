//
//  MIDIFileExporterTests.swift
//  EchoelmusicCoreTests
//
//  Verifies the Standard MIDI File (SMF Type 0) byte output of MIDIFileExporter.
//  Pure-logic tests — deterministic, no device needed.
//

import XCTest
@testable import Echoelmusic

final class MIDIFileExporterTests: XCTestCase {

    private func emptyGrid() -> [[Bool]] {
        Array(repeating: Array(repeating: false, count: 16), count: 8)
    }

    private func contains(_ haystack: Data, _ needle: [UInt8]) -> Bool {
        haystack.range(of: Data(needle)) != nil
    }

    func test_header_isValidSMFType0() {
        let data = MIDIFileExporter.export(steps: emptyGrid(), tempo: 120)
        XCTAssertEqual(Array(data.prefix(4)), Array("MThd".utf8))          // chunk id
        XCTAssertEqual(Array(data[4..<8]),  [0x00, 0x00, 0x00, 0x06])      // header length = 6
        XCTAssertEqual(Array(data[8..<10]), [0x00, 0x00])                  // format 0
        XCTAssertEqual(Array(data[10..<12]),[0x00, 0x01])                  // 1 track
        XCTAssertEqual(Array(data[12..<14]),[0x00, 0x60])                  // division = 96
        XCTAssertTrue(contains(data, Array("MTrk".utf8)))                  // track chunk present
        XCTAssertTrue(contains(data, [0xFF, 0x2F, 0x00]))                  // end-of-track meta
    }

    func test_tempo120_microsecondsPerQuarter() {
        let data = MIDIFileExporter.export(steps: emptyGrid(), tempo: 120)
        // 60_000_000 / 120 = 500000 = 0x07A120
        XCTAssertTrue(contains(data, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]))
    }

    func test_activeStep_producesNoteOnAndOff() {
        var grid = emptyGrid()
        grid[0][0] = true                                    // track 0 = kick (36) at step 0
        let data = MIDIFileExporter.export(steps: grid, tempo: 120, velocity: 100)
        XCTAssertTrue(contains(data, [0x99, 36, 100]))       // note on, channel 10
        XCTAssertTrue(contains(data, [0x89, 36, 0]))         // note off, channel 10
    }

    func test_emptyGrid_hasNoNoteEvents() {
        let data = MIDIFileExporter.export(steps: emptyGrid(), tempo: 120)
        for status: UInt8 in [0x99, 0x89] {
            XCTAssertFalse(data.contains(status), "empty grid must not emit note events")
        }
    }

    func test_vlq_encoding() {
        XCTAssertEqual(MIDIFileExporter.vlq(0),   [0x00])
        XCTAssertEqual(MIDIFileExporter.vlq(24),  [0x18])
        XCTAssertEqual(MIDIFileExporter.vlq(127), [0x7F])
        XCTAssertEqual(MIDIFileExporter.vlq(128), [0x81, 0x00])
        XCTAssertEqual(MIDIFileExporter.vlq(192), [0x81, 0x40])
    }

    func test_tempo_isClamped() {
        // 0 BPM would divide-by-zero; exporter clamps to >= 1.
        let data = MIDIFileExporter.export(steps: emptyGrid(), tempo: 0)
        XCTAssertTrue(contains(data, [0xFF, 0x51, 0x03]))    // tempo meta still well-formed
    }

    // MARK: - Combined (multi-track) export

    func test_combined_isSMFType1_withThreeTracks() {
        let data = MIDIFileExporter.exportCombined(notes: [], steps: emptyGrid(), tempo: 120)
        XCTAssertEqual(Array(data.prefix(4)), Array("MThd".utf8))
        XCTAssertEqual(Array(data[4..<8]),  [0x00, 0x00, 0x00, 0x06])      // header length = 6
        XCTAssertEqual(Array(data[8..<10]), [0x00, 0x01])                  // format 1
        XCTAssertEqual(Array(data[10..<12]),[0x00, 0x03])                  // 3 tracks
        XCTAssertEqual(Array(data[12..<14]),[0x00, 0x60])                  // division = 96
        // Three MTrk chunks (conductor + melody + drums).
        var count = 0, idx = data.startIndex
        while let r = data.range(of: Data("MTrk".utf8), in: idx..<data.endIndex) {
            count += 1; idx = r.upperBound
        }
        XCTAssertEqual(count, 3)
    }

    func test_combined_carriesTempoOnConductorTrack() {
        let data = MIDIFileExporter.exportCombined(notes: [], steps: emptyGrid(), tempo: 120)
        XCTAssertTrue(contains(data, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]))
    }

    func test_combined_hasMelodyChannel1_andDrumChannel10() {
        var grid = emptyGrid()
        grid[0][0] = true                                                  // kick at step 0
        let notes = [Note(pitch: 60, startStep: 0, lengthSteps: 2, velocity: 1.0)]
        let data = MIDIFileExporter.exportCombined(notes: notes, steps: grid, tempo: 120, velocity: 100)
        XCTAssertTrue(contains(data, [0x90, 60]))            // melody note-on, channel 1
        XCTAssertTrue(contains(data, [0x80, 60, 0]))         // melody note-off, channel 1
        XCTAssertTrue(contains(data, [0x99, 36, 100]))       // drum note-on, channel 10
        XCTAssertTrue(contains(data, [0x89, 36, 0]))         // drum note-off, channel 10
    }

    func test_combined_emptyTake_stillWellFormed() {
        let data = MIDIFileExporter.exportCombined(notes: [], steps: emptyGrid(), tempo: 120)
        XCTAssertTrue(contains(data, [0xFF, 0x2F, 0x00]))    // end-of-track present
        for status: UInt8 in [0x90, 0x99] {
            XCTAssertFalse(data.contains(status), "empty take must not emit note-ons")
        }
    }
}
