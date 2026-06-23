// MPEExpressionTests.swift
// Echoel — body→5D MPE expression mapping + MIDI encoders + channel rotation (pure).

import XCTest
@testable import Echoelmusic

final class MPEExpressionTests: XCTestCase {

    func testPitchBend14_centerLowHigh() {
        XCTAssertEqual(MPEExpression.pitchBend14(0).lsb, 0)
        XCTAssertEqual(MPEExpression.pitchBend14(0).msb, 64, "centre = 8192 → msb 64")
        XCTAssertEqual(MPEExpression.pitchBend14(-1).lsb, 0)
        XCTAssertEqual(MPEExpression.pitchBend14(-1).msb, 0, "min = 0")
        XCTAssertEqual(MPEExpression.pitchBend14(1).lsb, 127)
        XCTAssertEqual(MPEExpression.pitchBend14(1).msb, 127, "max = 16383")
    }

    func testPitchBend14_clampsOutOfRange() {
        XCTAssertEqual(MPEExpression.pitchBend14(5).msb, 127)
        XCTAssertEqual(MPEExpression.pitchBend14(-5).msb, 0)
    }

    func testFrom_coherenceBrightensSlide_breathPresses() {
        let dull  = MPEExpression.from(coherence: 0,   breathDepth: 0, hrvNormalized: 0.5)
        let clear = MPEExpression.from(coherence: 1,   breathDepth: 1, hrvNormalized: 0.5)
        XCTAssertEqual(dull.slideCC74, 0)
        XCTAssertEqual(clear.slideCC74, 127, "high coherence → full Slide/brightness")
        XCTAssertEqual(dull.pressure, 0)
        XCTAssertEqual(clear.pressure, 127, "deep breath → full Press")
        // HRV at 0.5 → no drift (centred bend).
        XCTAssertEqual(clear.bend, 0, accuracy: 1e-6)
    }

    func testFrom_hrvDriftIsSmallAndSigned() {
        let low  = MPEExpression.from(coherence: 0.5, breathDepth: 0.5, hrvNormalized: 0)
        let high = MPEExpression.from(coherence: 0.5, breathDepth: 0.5, hrvNormalized: 1)
        XCTAssertLessThan(low.bend, 0, "low HRV bends down")
        XCTAssertGreaterThan(high.bend, 0, "high HRV bends up")
        // ±50 cents within a ±48-semitone range → |bend| ≈ 0.0104, tiny + musical.
        XCTAssertLessThan(abs(high.bend), 0.02, "drift stays a micro-bend")
    }

    func testMemberChannelRoundRobin() {
        XCTAssertEqual(MPEExpression.memberChannel(noteIndex: 0), 2, "first member channel")
        XCTAssertEqual(MPEExpression.memberChannel(noteIndex: 14), 16, "15th member = ch 16")
        XCTAssertEqual(MPEExpression.memberChannel(noteIndex: 15), 2, "wraps round-robin")
        XCTAssertNotEqual(MPEExpression.memberChannel(noteIndex: 0),
                          MPEExpression.memberChannel(noteIndex: 1), "adjacent notes get distinct channels")
    }

    func testInitClampsBend() {
        XCTAssertEqual(MPEExpression(slideCC74: 0, pressure: 0, bend: 9).bend, 1, accuracy: 1e-6)
        XCTAssertEqual(MPEExpression(slideCC74: 0, pressure: 0, bend: -9).bend, -1, accuracy: 1e-6)
    }

    func testMIDI2NoteOnMessages_carriesAll5Dimensions() {
        let e = MPEExpression(slideCC74: 127, pressure: 64, bend: 0)   // centre bend
        let msgs = e.midi2NoteOnMessages(channel: 0, note: 60, strike: 1.0)
        XCTAssertEqual(msgs.count, 4, "note-on + per-note bend + per-note CC74 + channel pressure")

        // [0] Note On — opcode 0x9, full 16-bit Strike velocity.
        XCTAssertEqual((msgs[0].0 >> 20) & 0xF, 0x9)
        XCTAssertEqual(msgs[0].1 >> 16, 0xFFFF, "strike 1.0 → full velocity")

        // [1] Per-note pitch bend — opcode 0x6, centre = 0x8000_0000 (no drift).
        XCTAssertEqual((msgs[1].0 >> 20) & 0xF, 0x6)
        XCTAssertEqual((msgs[1].0 >> 8) & 0xFF, 60, "carries the note (per-note)")
        XCTAssertEqual(msgs[1].1, 0x8000_0000, "centre bend = no drift")

        // [2] Per-note controller — opcode 0x1, index CC74, full Slide.
        XCTAssertEqual((msgs[2].0 >> 20) & 0xF, 0x1)
        XCTAssertEqual(msgs[2].0 & 0xFF, 74, "CC74 = Slide/brightness")
        XCTAssertEqual(msgs[2].1, 0xFFFF_FFFF, "slide 127 → full scale")

        // [3] Channel pressure — opcode 0xD, centre Press.
        XCTAssertEqual((msgs[3].0 >> 20) & 0xF, 0xD)
        XCTAssertEqual(msgs[3].1, 0x8000_0000, "pressure 64 → 32-bit centre")
    }
}
