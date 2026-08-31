// MIDIEventParseTests.swift
// H10 (#30) — the pure MIDI-input laws, Linux-CI-tested: UMP word → event
// mapping (behavior-identical to the pre-H10 inline parsing, pinned case by
// case) and the batch queue's FIFO / one-drain-per-burst / honest-overflow
// contract that replaced the Task-per-event flood.

import XCTest
@testable import Echoelmusic

final class MIDIEventParseTests: XCTestCase {

    // MARK: - UMP word builders (message type in the top nibble, group 0)

    /// MIDI 1.0 channel-voice word: [0x2 | group][status|ch][data1][data2]
    private func midi1(_ status: UInt32, ch: UInt32, d1: UInt32, d2: UInt32) -> UInt32 {
        (0x2 << 28) | ((status | ch) << 16) | (d1 << 8) | d2
    }

    /// MIDI 2.0 channel-voice word0: [0x4][statusNibble|ch in 20-16][note in 15-8]
    private func midi2w0(_ statusNibble: UInt32, ch: UInt32, note: UInt32) -> UInt32 {
        (0x4 << 28) | (statusNibble << 20) | (ch << 16) | (note << 8)
    }

    // MARK: - MIDI 1.0

    func testMIDI1_noteOn_mapsNoteVelocityChannel() {
        let e = MIDIEventParse.event(word0: midi1(0x90, ch: 3, d1: 60, d2: 127), word1: nil)
        XCTAssertEqual(e, .noteOn(note: 60, velocity: 1.0, channel: 3))
    }

    func testMIDI1_noteOnVelocityZero_isNoteOff() {
        let e = MIDIEventParse.event(word0: midi1(0x90, ch: 0, d1: 60, d2: 0), word1: nil)
        XCTAssertEqual(e, .noteOff(note: 60, channel: 0), "vel-0 note-on IS a note-off (MIDI law)")
    }

    func testMIDI1_noteOff() {
        let e = MIDIEventParse.event(word0: midi1(0x80, ch: 1, d1: 47, d2: 0), word1: nil)
        XCTAssertEqual(e, .noteOff(note: 47, channel: 1))
    }

    func testMIDI1_cc_normalizes() {
        guard case .cc(let num, let value, let channel)? =
                MIDIEventParse.event(word0: midi1(0xB0, ch: 2, d1: 74, d2: 64), word1: nil) else {
            return XCTFail("expected cc")
        }
        XCTAssertEqual(num, 74)
        XCTAssertEqual(channel, 2)
        XCTAssertEqual(value, 64.0 / 127.0, accuracy: 1e-6)
    }

    func testMIDI1_pitchBend_centerMaxMin() throws {
        // center: lsb 0 msb 64 → 0
        var e = try XCTUnwrap(MIDIEventParse.event(word0: midi1(0xE0, ch: 0, d1: 0, d2: 64), word1: nil))
        guard case .pitchBend(let center, _) = e else { return XCTFail() }
        XCTAssertEqual(center, 0, accuracy: 1e-6)
        // max: lsb 127 msb 127 → ≈ +1
        e = try XCTUnwrap(MIDIEventParse.event(word0: midi1(0xE0, ch: 0, d1: 127, d2: 127), word1: nil))
        guard case .pitchBend(let up, _) = e else { return XCTFail() }
        XCTAssertEqual(up, 8191.0 / 8192.0, accuracy: 1e-6)
        // min: lsb 0 msb 0 → −1
        e = try XCTUnwrap(MIDIEventParse.event(word0: midi1(0xE0, ch: 0, d1: 0, d2: 0), word1: nil))
        guard case .pitchBend(let down, _) = e else { return XCTFail() }
        XCTAssertEqual(down, -1, accuracy: 1e-6)
        // mixed low bits below center: lsb 127 msb 0 → −8065/8192 (the OR-as-add law)
        e = try XCTUnwrap(MIDIEventParse.event(word0: midi1(0xE0, ch: 0, d1: 127, d2: 0), word1: nil))
        guard case .pitchBend(let mixed, _) = e else { return XCTFail() }
        XCTAssertEqual(mixed, -8065.0 / 8192.0, accuracy: 1e-6)
    }

    // MARK: - MIDI 2.0

    func testMIDI2_noteOn_16BitVelocity() {
        let e = MIDIEventParse.event(word0: midi2w0(0x9, ch: 5, note: 72),
                                     word1: 0xFFFF_0000)
        XCTAssertEqual(e, .noteOn(note: 72, velocity: 1.0, channel: 5))
    }

    func testMIDI2_noteOff() {
        let e = MIDIEventParse.event(word0: midi2w0(0x8, ch: 0, note: 72), word1: 0)
        XCTAssertEqual(e, .noteOff(note: 72, channel: 0))
    }

    func testMIDI2_cc_32Bit() {
        guard case .cc(let num, let value, _)? =
                MIDIEventParse.event(word0: midi2w0(0xB, ch: 0, note: 1),
                                     word1: UInt32.max) else {
            return XCTFail("expected cc")
        }
        XCTAssertEqual(num, 1)
        XCTAssertEqual(value, 1.0, accuracy: 1e-6)
    }

    func testMIDI2_pitchBend_signed32() {
        guard case .pitchBend(let value, _)? =
                MIDIEventParse.event(word0: midi2w0(0xE, ch: 0, note: 0),
                                     word1: UInt32(bitPattern: Int32.max)) else {
            return XCTFail("expected bend")
        }
        XCTAssertEqual(value, 1.0, accuracy: 1e-6)
    }

    // MARK: - Channel Pressure (#939) — MPE's PRESS dimension

    /// ⭐ Before #939 this fell to `default: return nil` in BOTH protocols: the parser decoded
    /// four things and `MIDIInEvent` had no case to carry a fifth, so a player leaning into a
    /// key sent bytes that were discarded one layer below any wiring.
    func testMIDI1_channelPressure_normalizes() {
        let e = MIDIEventParse.event(word0: midi1(0xD0, ch: 5, d1: 64, d2: 0), word1: nil)
        XCTAssertEqual(e, .channelPressure(value: 64.0 / 127.0, channel: 5))
    }

    /// ⚠️ THE TRAP THIS SLICE WAS MOST LIKELY TO FALL INTO, so it gets its own claim.
    /// Channel Pressure is a TWO-byte message — status plus ONE data byte — while every
    /// neighbouring case reads its level out of `d2`, the SECOND data byte. Copying that shape
    /// reads the filler instead of the pressure: always 0, never an error, and indistinguishable
    /// from a player who is simply not pressing. `d1` is full scale here and `d2` is deliberately
    /// non-zero and DIFFERENT, so a `d2` implementation cannot pass by coincidence.
    func testMIDI1_channelPressure_readsTheFirstDataByteNotTheSecond() {
        let e = MIDIEventParse.event(word0: midi1(0xD0, ch: 0, d1: 127, d2: 40), word1: nil)
        XCTAssertEqual(e, .channelPressure(value: 1.0, channel: 0),
                       "pressure must come from data byte 1; reading data byte 2 gives 40/127")
    }

    func testMIDI2_channelPressure_32Bit() {
        let e = MIDIEventParse.event(word0: midi2w0(0xD, ch: 2, note: 0), word1: UInt32.max)
        XCTAssertEqual(e, .channelPressure(value: 1.0, channel: 2))
    }

    func testMIDI2_channelPressure_missingWord1_isDropped() {
        XCTAssertNil(MIDIEventParse.event(word0: midi2w0(0xD, ch: 2, note: 0), word1: nil))
    }

    /// COUNTERWEIGHT: adding a fifth case must not have moved the other four. A status byte
    /// that is still unknown has to stay dropped, or "parses more" quietly became "parses
    /// anything".
    func testAnUnknownStatusIsStillDropped() {
        XCTAssertNil(MIDIEventParse.event(word0: midi1(0xA0, ch: 0, d1: 60, d2: 64), word1: nil),
                     "0xA0 (poly aftertouch) is NOT channel pressure and is still unsupported")
        XCTAssertNil(MIDIEventParse.event(word0: midi2w0(0xA, ch: 0, note: 60), word1: 1),
                     "MIDI 2.0 0xA likewise")
    }

    func testMIDI2_missingWord1_isDropped() {
        XCTAssertNil(MIDIEventParse.event(word0: midi2w0(0x9, ch: 0, note: 60), word1: nil))
    }

    func testUnknownMessageType_isDropped() {
        XCTAssertNil(MIDIEventParse.event(word0: 0xF000_0000, word1: nil))
        XCTAssertNil(MIDIEventParse.event(word0: midi1(0xA0, ch: 0, d1: 1, d2: 1), word1: nil),
                     "poly aftertouch was never handled — unchanged")
    }

    // MARK: - Batch queue (flood → one drain per burst, FIFO, honest overflow)

    func testQueue_firstPushSchedulesDrain_restOfBurstDoesNot() {
        let q = MIDIInEventQueue()
        XCTAssertTrue(q.push(.noteOff(note: 1, channel: 0)), "first push arms the ONE drain")
        XCTAssertFalse(q.push(.noteOff(note: 2, channel: 0)))
        XCTAssertFalse(q.push(.noteOff(note: 3, channel: 0)))
        let (events, dropped) = q.drain()
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(dropped, 0)
        XCTAssertTrue(q.push(.noteOff(note: 4, channel: 0)), "after a drain, the next push re-arms")
    }

    func testQueue_preservesFIFO_noteOnBeforeItsOff() {
        let q = MIDIInEventQueue()
        _ = q.push(.noteOn(note: 60, velocity: 1, channel: 0))
        _ = q.push(.noteOff(note: 60, channel: 0))
        let (events, _) = q.drain()
        XCTAssertEqual(events, [.noteOn(note: 60, velocity: 1, channel: 0),
                                .noteOff(note: 60, channel: 0)],
                       "the whole point: separate Tasks could reorder these — the queue cannot")
    }

    func testQueue_overflow_dropsNewestAndCounts() {
        let q = MIDIInEventQueue()
        for i in 0..<(MIDIInEventQueue.capacity + 5) {
            _ = q.push(.noteOff(note: i & 0x7F, channel: 0))
        }
        let (events, dropped) = q.drain()
        XCTAssertEqual(events.count, MIDIInEventQueue.capacity)
        XCTAssertEqual(dropped, 5, "overflow is counted honestly, never silent")
        XCTAssertEqual(events.first, .noteOff(note: 0, channel: 0), "oldest kept (drop-newest)")
    }

    func testQueue_burstWithDrops_stillArmsADrain_andReportsThem() {
        // A push that DROPS (queue full) must still leave a drain scheduled —
        // the drop report needs that drain to be delivered.
        let q = MIDIInEventQueue()
        var armed = false
        for _ in 0..<(MIDIInEventQueue.capacity + 1) {
            if q.push(.noteOff(note: 1, channel: 0)) { armed = true }
        }
        XCTAssertTrue(armed, "the burst containing drops arms exactly one drain")
        let (_, droppedCount) = q.drain()
        XCTAssertEqual(droppedCount, 1, "the drop is reported at that drain")
    }

    func testQueue_emptyDrain_isHarmless() {
        let q = MIDIInEventQueue()
        let (events, dropped) = q.drain()
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(dropped, 0)
        XCTAssertTrue(q.push(.noteOff(note: 1, channel: 0)), "still arms normally afterwards")
    }
}
