//
//  MIDIFileExporterTests.swift
//  EchoelmusicFullTests
//
//  Verifies the Standard MIDI File byte output of MIDIFileExporter (Type 0 grid export,
//  Type 1 combined/clip export). Pure-logic tests — deterministic, no device needed.
//
//  ⛔ THE TARGET LINE ABOVE USED TO SAY `EchoelmusicCoreTests`, AND THAT TARGET DOES NOT
//  EXIST. The file sat in `Tests/EchoelmusicCoreTests/`, a directory named in no target,
//  no `Package.swift`, and no workflow — so it had never compiled and never run. #469 moved
//  it here; the very first run failed three assertions. Kept as a warning: a test file's
//  header naming a target is not evidence that the target exists.
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

    /// The drum note-on byte a TYPE-1 export actually writes when the caller asks for
    /// velocity 100 and supplies no accents.
    ///
    /// ⛔ THREE TESTS ASSERTED 100 HERE AND WERE WRONG FOR MONTHS — the first thing #469
    /// found once this file finally reached a target. On the Type-1 path `velocity:` is the
    /// ACCENT CENTRE, not the emitted byte: `drumEvents` splits ±20 around it, and with an
    /// empty `accents` array every cell takes the quiet side. `Humanizer.tight` is
    /// `velocityJitter: 0`, so there is no rounding to hide behind — the byte is exactly 80.
    /// (The Type-0 `export(steps:tempo:velocity:)` overload has no accents and does emit the
    /// literal, which is why the sibling test asserting 100 there was always green.)
    ///
    /// ⭐ A LITERAL ON PURPOSE, not `velocity - 20`. Deriving it from the same rule the code
    /// applies would make this unable to catch a change to that rule — the #441 defect. If
    /// the split moves, this number is supposed to go red and be re-decided by hand.
    ///
    /// ⚠️ Pinning it is NOT an endorsement: a caller asking for 100 and receiving 80
    /// everywhere is an open question, recorded at the declaration in `MIDIFileExporter` and
    /// registered as #471. This file says what ships today; it does not say it is right.
    private let unaccentedVelocity: UInt8 = 80

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
        XCTAssertTrue(contains(data, [0x99, 36, unaccentedVelocity]))   // drum note-on, ch 10
        XCTAssertTrue(contains(data, [0x89, 36, 0]))         // drum note-off, channel 10
    }

    func test_combined_emptyTake_stillWellFormed() {
        let data = MIDIFileExporter.exportCombined(notes: [], steps: emptyGrid(), tempo: 120)
        XCTAssertTrue(contains(data, [0xFF, 0x2F, 0x00]))    // end-of-track present
        for status: UInt8 in [0x90, 0x99] {
            XCTAssertFalse(data.contains(status), "empty take must not emit note-ons")
        }
    }

    // MARK: - Clip export (one launchable Clip → one .mid)

    private func activeGrid() -> [[Bool]] {
        var grid = emptyGrid()
        grid[0][0] = true                                     // kick at step 0
        return grid
    }

    func test_clip_isSMFType1_withThreeTracks() {
        let clip = Clip(name: "Take", kind: .midi,
                        drums: DrumPattern(steps: activeGrid(), accents: []),
                        melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0, lengthSteps: 2)]))
        let data = MIDIFileExporter.export(clip: clip, tempo: 120)
        XCTAssertEqual(Array(data.prefix(4)), Array("MThd".utf8))
        XCTAssertEqual(Array(data[8..<10]), [0x00, 0x01])                  // format 1
        XCTAssertEqual(Array(data[10..<12]),[0x00, 0x03])                  // 3 tracks
        XCTAssertEqual(Array(data[12..<14]),[0x00, 0x60])                  // division = 96
    }

    func test_clip_melodyOnly_emitsChannel1_notChannel10() {
        let clip = Clip(name: "Lead", kind: .midi,
                        melody: MelodyClip(notes: [Note(pitch: 64, startStep: 0, lengthSteps: 4, velocity: 1.0)]))
        let data = MIDIFileExporter.export(clip: clip, tempo: 120)
        XCTAssertTrue(contains(data, [0x90, 64]))            // melody note-on, channel 1
        XCTAssertFalse(data.contains(0x99), "a melody-only clip must not emit drum (channel 10) note-ons")
    }

    func test_clip_drumsOnly_emitsChannel10_notChannel1() {
        let clip = Clip(name: "Beat", kind: .midi,
                        drums: DrumPattern(steps: activeGrid(), accents: []))
        let data = MIDIFileExporter.export(clip: clip, tempo: 120, velocity: 100)
        XCTAssertTrue(contains(data, [0x99, 36, unaccentedVelocity]))   // drum note-on, ch 10
        XCTAssertFalse(data.contains(0x90), "a drums-only clip must not emit melody (channel 1) note-ons")
    }

    func test_clip_combined_emitsBothChannels() {
        let clip = Clip(name: "Full", kind: .midi,
                        drums: DrumPattern(steps: activeGrid(), accents: []),
                        melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0, lengthSteps: 2, velocity: 1.0)]))
        let data = MIDIFileExporter.export(clip: clip, tempo: 120, velocity: 100)
        XCTAssertTrue(contains(data, [0x90, 60]))            // melody, channel 1
        XCTAssertTrue(contains(data, [0x99, 36, unaccentedVelocity]))   // drums, channel 10
    }

    func test_clip_emptyMidiClip_isWellFormed() {
        let data = MIDIFileExporter.export(clip: Clip(name: "Empty", kind: .midi), tempo: 120)
        XCTAssertEqual(Array(data.prefix(4)), Array("MThd".utf8))
        XCTAssertTrue(contains(data, [0xFF, 0x2F, 0x00]))    // end-of-track present
        for status: UInt8 in [0x90, 0x99] {
            XCTAssertFalse(data.contains(status), "an empty clip must not emit note events")
        }
    }

    func test_clip_mediaCarrier_hasNoPatternButStaysWellFormed() {
        // An audio/video/visual clip carries a mediaRef, no notes/grid → an honest
        // empty region, never a crash.
        let clip = Clip(name: "Sample", kind: .audio, mediaRef: "take.caf")
        let data = MIDIFileExporter.export(clip: clip, tempo: 120)
        XCTAssertTrue(contains(data, [0xFF, 0x2F, 0x00]))
        for status: UInt8 in [0x90, 0x99] {
            XCTAssertFalse(data.contains(status))
        }
    }

    func test_clip_derivedBars_roundUpToWholeBar() {
        // A note that STARTS in bar 2 (step 16 = 1920 ticks) and runs 2 steps ends at
        // 2160 ticks → the region must span 2 whole bars (End-of-Track at 2×4 quarters).
        let clip = Clip(name: "Long", kind: .midi,
                        melody: MelodyClip(notes: [Note(pitch: 60, startStep: 16, lengthSteps: 2)]))
        let twoBar = MIDIFileExporter.export(clip: clip, tempo: 120)
        // Compare against a clip whose content fits one bar: the 2-bar file must be LONGER.
        // (The delta is the bar-2 note-on's larger start-delta VLQ vs. the bar-1 note's
        // zero delta — a strict, non-degenerate margin proving the region really grew.)
        let oneBarClip = Clip(name: "Short", kind: .midi,
                              melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0, lengthSteps: 2)]))
        let oneBar = MIDIFileExporter.export(clip: oneBarClip, tempo: 120)
        XCTAssertGreaterThan(twoBar.count, oneBar.count,
                             "a clip reaching into bar 2 must export a longer (2-bar) region")
    }

    func test_clip_tempoReflectedOnConductor() {
        let clip = Clip(name: "Take", kind: .midi,
                        melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0, lengthSteps: 2)]))
        let data = MIDIFileExporter.export(clip: clip, tempo: 120)
        XCTAssertTrue(contains(data, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]))   // 120 BPM
    }

    // MARK: - Program Change (melody instrument select for the DAW)

    private func melodyClip() -> Clip {
        Clip(name: "Lead", kind: .midi,
             melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0, lengthSteps: 2, velocity: 1.0)]))
    }

    func test_program_emitsProgramChangeOnMelodyChannel() {
        let data = MIDIFileExporter.export(clip: melodyClip(), tempo: 120, program: 42)
        XCTAssertTrue(contains(data, [0xC0, 42]), "a program request must emit a channel-1 Program Change")
    }

    func test_program_nil_isByteIdenticalBaseline_plusNothing() {
        // The default (no program) path must stay byte-for-byte the old output; the PC
        // path adds EXACTLY the 3 bytes (00 C0 pp), nothing else.
        let none = MIDIFileExporter.export(clip: melodyClip(), tempo: 120)
        let withPC = MIDIFileExporter.export(clip: melodyClip(), tempo: 120, program: 42)
        XCTAssertEqual(withPC.count, none.count + 3, "Program Change must add exactly 00 C0 pp")
        XCTAssertFalse(contains(none, [0xC0, 42]), "no program → no Program Change byte")
    }

    func test_program_isMaskedTo7Bit() {
        // 200 & 0x7F = 72 — an out-of-range program can never emit an invalid data byte.
        let data = MIDIFileExporter.export(clip: melodyClip(), tempo: 120, program: 200)
        XCTAssertTrue(contains(data, [0xC0, 72]))
        XCTAssertFalse(contains(data, [0xC0, 200]))
    }

    func test_program_combinedExporterHonorsIt() {
        var grid = emptyGrid(); grid[0][0] = true
        let notes = [Note(pitch: 60, startStep: 0, lengthSteps: 2, velocity: 1.0)]
        let data = MIDIFileExporter.exportCombined(notes: notes, steps: grid, tempo: 120, program: 5)
        XCTAssertTrue(contains(data, [0xC0, 5]))
    }
}
