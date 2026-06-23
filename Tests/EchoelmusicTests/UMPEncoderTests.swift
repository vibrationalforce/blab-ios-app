// UMPEncoderTests.swift
// Echoel — Universal MIDI Packet encoder: MIDI 1.0 + MIDI 2.0 channel-voice words
// and the MMA min-center-max resolution scaling. Pure + deterministic.

import XCTest
@testable import Echoelmusic

final class UMPEncoderTests: XCTestCase {

    // MARK: - MIDI 1.0 (type 0x2, one word)

    func testMIDI1NoteOn_packsExactlyLikeMIDIOutput() {
        // MIDIOutput.send builds: (0x2<<28)|(status<<16)|(data1<<8)|data2 on group 0.
        let w = UMPEncoder.note1On(channel: 0, note: 60, velocity: 100)
        XCTAssertEqual(w, (UInt32(0x2) << 28) | (UInt32(0x90) << 16) | (UInt32(60) << 8) | 100)
    }

    func testMIDI1_groupAndMaskedData() {
        let w = UMPEncoder.controlChange1(channel: 3, index: 74, value: 64, group: 5)
        XCTAssertEqual((w >> 28) & 0xF, 0x2, "message type 0x2")
        XCTAssertEqual((w >> 24) & 0xF, 5, "group 5")
        XCTAssertEqual((w >> 16) & 0xFF, 0xB3, "CC on channel 3")
        XCTAssertEqual((w >> 8) & 0xFF, 74)
        XCTAssertEqual(w & 0xFF, 64)
    }

    func testMIDI1PitchBend_splits14Bit() {
        let w = UMPEncoder.pitchBend1(channel: 0, value14: 8192)   // centre
        XCTAssertEqual((w >> 8) & 0xFF, 0, "lsb of 8192")
        XCTAssertEqual(w & 0xFF, 0x40, "msb of 8192 = 64")
    }

    // MARK: - MIDI 2.0 (type 0x4, two words)

    func testMIDI2NoteOn_layoutAndVelocity() {
        let (msw, lsw) = UMPEncoder.note2On(channel: 2, note: 64, velocity16: 0xABCD)
        XCTAssertEqual((msw >> 28) & 0xF, 0x4, "message type 0x4")
        XCTAssertEqual((msw >> 20) & 0xF, 0x9, "note-on opcode")
        XCTAssertEqual((msw >> 16) & 0xF, 2, "channel 2")
        XCTAssertEqual((msw >> 8) & 0xFF, 64, "note number")
        XCTAssertEqual(lsw >> 16, 0xABCD, "16-bit velocity in high half of data word")
    }

    func testMIDI2PerNotePitchBend_opcodeAndCenter() {
        let (msw, lsw) = UMPEncoder.perNotePitchBend2(channel: 0, note: 60, value32: 0x8000_0000)
        XCTAssertEqual((msw >> 20) & 0xF, 0x6, "per-note pitch bend opcode")
        XCTAssertEqual((msw >> 8) & 0xFF, 60, "carries the note number (per-note)")
        XCTAssertEqual(lsw, 0x8000_0000, "centre bend")
    }

    func testMIDI2PerNoteController_carriesIndexAndNote() {
        let (msw, lsw) = UMPEncoder.perNoteController2(channel: 1, note: 72, index: 74, value32: 0xFFFF_FFFF)
        XCTAssertEqual((msw >> 20) & 0xF, 0x1, "assignable per-note controller opcode")
        XCTAssertEqual((msw >> 8) & 0xFF, 72, "note")
        XCTAssertEqual(msw & 0xFF, 74, "controller index (CC74/Slide)")
        XCTAssertEqual(lsw, 0xFFFF_FFFF)
    }

    // MARK: - Resolution scaling (MMA anchors)

    func testScaleUp7to16_preservesAnchors() {
        XCTAssertEqual(UMPEncoder.velocity7to16(0), 0, "zero → zero")
        XCTAssertEqual(UMPEncoder.velocity7to16(64), 0x8000, "7-bit centre → 16-bit centre")
        XCTAssertEqual(UMPEncoder.velocity7to16(127), 0xFFFF, "max → full scale")
    }

    func testScaleUp14to32_pitchBendAnchors() {
        XCTAssertEqual(UMPEncoder.bend14to32(0), 0, "min")
        XCTAssertEqual(UMPEncoder.bend14to32(8192), 0x8000_0000, "centre 8192 → 0x80000000")
        XCTAssertEqual(UMPEncoder.bend14to32(0x3FFF), 0xFFFF_FFFF, "max")
    }

    func testScaleUp_isMonotonic() {
        var prev: UInt32 = 0
        for v in 0...127 {
            let s = UMPEncoder.cc7to32(UInt8(v))
            if v > 0 { XCTAssertGreaterThan(s, prev, "scaling is strictly increasing at \(v)") }
            prev = s
        }
    }
}
