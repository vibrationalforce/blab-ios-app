// MIDIExportMelodyOnlyTests.swift
// Echoel — #188. The MIDI export door came back, and with it a DECISION that is
// invisible in the UI and therefore needs a test to survive: the take is exported
// MELODY ONLY. `BioComposer` still fills `PatternEngine.steps` with a groove, but since
// the drums were deleted (#166/#167) nothing renders that grid — it is a bar clock now.
// Tiling it into the .mid would hand a DAW a drum track the user never heard.
//
// ⛔ HONEST SCOPE, corrected by review: these tests pin `exportCombined`'s BEHAVIOUR given
// empty steps — they do NOT pin that `exportMIDI()` passes empty steps. Restoring
// `steps: LoopCutter.tile(grid: beatPlayer.pattern.steps, bars: bars)` at the call site
// leaves this whole file green. The first version of this header claimed the opposite
// ("these tests fail loudly if someone restores it"), which is the worst kind of wrong: a
// false sense of coverage over the exact line that needs it.
//
// The call site is a `private func` inside a 4000-line `@MainActor` SwiftUI view with no
// injection seam, so testing it means extracting the export payload into a pure function
// first. That is a real slice, not a comment — deliberately not smuggled into this one.
// Until then the guard is the comment at the call site plus this paragraph.
//
// The second half pins what melody-only must NOT cost. The obvious way to drop drums is
// to switch to the Type-0 `export(notes:tempo:)`, which would silently lose the key
// signature, the time signature and the whole-bar End-of-Track anchoring — i.e. exactly
// the "in der DAW weiterarbeiten" properties the export exists for. So the format is
// pinned too.

import XCTest
@testable import Echoelmusic

final class MIDIExportMelodyOnlyTests: XCTestCase {

    private func take() -> [Note] {
        // Two bars of quarter notes, so `bars: 2` is a real region, not a degenerate one.
        (0..<8).map { i in
            Note(pitch: 60 + i, startTick: i * Note.ticksPerQuarter,
                 lengthTicks: Note.ticksPerQuarter, velocity: 0.8)
        }
    }

    /// Every `MTrk` chunk in a Type-1 file, as raw payload slices.
    private func trackPayloads(_ data: Data) -> [Data] {
        var out: [Data] = []
        let bytes = [UInt8](data)
        var i = 0
        while i + 8 <= bytes.count {
            if bytes[i] == 0x4D, bytes[i + 1] == 0x54, bytes[i + 2] == 0x72, bytes[i + 3] == 0x6B {
                let len = (Int(bytes[i + 4]) << 24) | (Int(bytes[i + 5]) << 16)
                        | (Int(bytes[i + 6]) << 8)  | Int(bytes[i + 7])
                let start = i + 8
                guard start + len <= bytes.count else { break }
                out.append(Data(bytes[start..<(start + len)]))
                i = start + len
            } else {
                i += 1
            }
        }
        return out
    }

    /// True if the payload contains any note-on with a non-zero velocity on any channel.
    ///
    /// ⛔ THE NAIVE VERSION OF THIS WAS A LOADED GUN — recorded because the trap is not
    /// obvious. It scanned every byte for high nibble 9, and its comment claimed the empty
    /// drum payload was `[0x00,0xFF,0x03,5] + "Drums" + [0x00,0xFF,0x2F,0x00]`. That was
    /// WRONG: `serializeTrack` writes `vlq(endTick - lastTick)` before End-of-Track, and
    /// `lastTick` is 0 on an empty track, so the payload carries `vlq(bars × 384)`. At
    /// `bars: 8` that is `0x98 0x00` — high nibble 9, followed by `0xFF` — and the scanner
    /// reported a note-on in a track with no notes. The test passed only because the fixture
    /// happened to use `bars: 2` (`0x86`). Anyone "making the fixture realistic" by using
    /// the app's default 8 bars would have hit a red test with no visible cause.
    ///
    /// So it parses properly now: walk delta-VLQ → event, skipping meta/sysex by their
    /// declared length, and honour running status. `bars` is then just a number again.
    private func hasSoundingNotes(_ payload: Data) -> Bool {
        let b = [UInt8](payload)
        var i = 0
        var runningStatus: UInt8 = 0
        while i < b.count {
            // Delta time: VLQ, continuation bit high.
            while i < b.count, b[i] & 0x80 != 0 { i += 1 }
            guard i < b.count else { return false }
            i += 1                                   // final VLQ byte
            guard i < b.count else { return false }
            var status = b[i]
            if status & 0x80 != 0 { i += 1 } else { status = runningStatus }  // running status
            switch status {
            case 0xFF:                               // meta: type + VLQ length + payload
                guard i + 1 < b.count else { return false }
                i += 1                               // meta type
                var len = 0
                while i < b.count {
                    len = (len << 7) | Int(b[i] & 0x7F)
                    let more = b[i] & 0x80 != 0
                    i += 1
                    if !more { break }
                }
                i += len
            case 0xF0, 0xF7:                         // sysex: VLQ length + payload
                var len = 0
                while i < b.count {
                    len = (len << 7) | Int(b[i] & 0x7F)
                    let more = b[i] & 0x80 != 0
                    i += 1
                    if !more { break }
                }
                i += len
            default:
                runningStatus = status
                let dataBytes = (status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0) ? 1 : 2
                if status & 0xF0 == 0x90, i + 1 < b.count, b[i + 1] > 0 { return true }
                i += dataBytes
            }
        }
        return false
    }

    // MARK: - The decision

    func testEmptySteps_produceADrumTrackWithNoNotes() {
        let data = MIDIFileExporter.exportCombined(
            notes: take(), steps: [], accents: [],
            tempo: 96, bars: 2, keyRootPitchClass: 2, keyIsMinor: true)
        let tracks = trackPayloads(data)
        XCTAssertEqual(tracks.count, 3, "conductor + melody + drums — the file shape is unchanged")
        XCTAssertTrue(hasSoundingNotes(tracks[1]), "the melody must actually be in there")
        XCTAssertFalse(hasSoundingNotes(tracks[2]),
                       "the drum track must be EMPTY — the app plays no drums, so the .mid must not either")
    }

    func testNonEmptySteps_wouldEmitDrumNotes_soTheEmptyCaseIsNotVacuous() {
        // Falsifiability guard: without this, `testEmptySteps_…` would still pass if
        // `exportCombined` had simply stopped writing drums altogether, and the test would
        // be pinning nothing. One filled step must still produce a sounding drum note.
        var steps = Array(repeating: Array(repeating: false, count: 16), count: 8)
        steps[0][0] = true
        let data = MIDIFileExporter.exportCombined(
            notes: take(), steps: steps, accents: [],
            tempo: 96, bars: 2, keyRootPitchClass: 2, keyIsMinor: true)
        let tracks = trackPayloads(data)
        XCTAssertEqual(tracks.count, 3)
        XCTAssertTrue(hasSoundingNotes(tracks[2]),
                      "the exporter CAN write drums — so the empty-steps result above is a real choice")
    }

    // MARK: - What melody-only must not cost

    func testMelodyOnlyStillCarriesTempoTimeAndKeySignature() {
        // The Type-0 `export(notes:tempo:)` would drop all three. The conductor track is
        // why `exportCombined` stays the engine even with no drums.
        let data = MIDIFileExporter.exportCombined(
            notes: take(), steps: [], accents: [],
            tempo: 96, bars: 2, keyRootPitchClass: 2, keyIsMinor: true)
        guard let conductor = trackPayloads(data).first else {
            return XCTFail("no conductor track")
        }
        let b = [UInt8](conductor)
        func containsMeta(_ type: UInt8) -> Bool {
            for i in 0..<b.count where b[i] == 0xFF {
                if i + 1 < b.count, b[i + 1] == type { return true }
            }
            return false
        }
        XCTAssertTrue(containsMeta(0x51), "tempo meta")
        XCTAssertTrue(containsMeta(0x58), "time-signature meta")
        XCTAssertTrue(containsMeta(0x59), "key-signature meta — the Tonart the DAW shows")
    }

    func testMelodyOnlyIsStillATypeOneMultiTrackFile() {
        // Header: "MThd", length 6, format, ntracks, division. Format must stay 1 — a
        // Type-0 switch is the exact regression this pins.
        let data = MIDIFileExporter.exportCombined(
            notes: take(), steps: [], accents: [], tempo: 96, bars: 2)
        let b = [UInt8](data)
        XCTAssertEqual(Array(b.prefix(4)), Array("MThd".utf8))
        XCTAssertEqual((Int(b[8]) << 8) | Int(b[9]), 1, "format 1")
        XCTAssertEqual((Int(b[10]) << 8) | Int(b[11]), 3, "three tracks")
    }
}
