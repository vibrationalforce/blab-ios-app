// UMPEncoder.swift
// Echoel — Universal MIDI Packet (UMP) encoder: the wire format for BOTH MIDI 1.0
// and MIDI 2.0 channel-voice messages, as a PURE, fully unit-tested value core (no
// CoreMIDI, so it builds + tests everywhere — ci.yml runs it for real). This is the
// industry-standard transport for Echoel's "multidimensional" output:
//
//   • MIDI 1.0 over UMP  — one 32-bit word (message type 0x2). Universal; this is
//     the exact packing MIDIOutput already sends, now centralised + tested.
//   • MIDI 2.0           — two 32-bit words (message type 0x4) with 16-bit velocity,
//     32-bit controllers, and crucially PER-NOTE pitch bend + per-note controllers.
//     That per-note resolution is the natural high-res home for the body's 5D MPE
//     expression (see MPEExpression): each voice gets its own continuous
//     Slide/Press/Glide without the 15-channel MPE workaround.
//
// Wiring a MIDI-2.0 CoreMIDI source (MIDISourceCreateWithProtocol ._2_0) that emits
// these is a later, iOS-gated slice; this core just guarantees the bytes are right.
// Reference: MMA "Universal MIDI Packet (UMP) Format and MIDI 2.0 Protocol" (M2-104-UM).

import Foundation

public enum UMPEncoder {

    // MARK: - MIDI 1.0 (message type 0x2 — one 32-bit word)

    /// Pack a MIDI 1.0 channel-voice message (status byte incl. channel nibble + up
    /// to two 7-bit data bytes) into one 32-bit UMP word on `group` (0…15).
    /// Layout: [mt 0x2 | group | status | data1 | data2].
    public static func midi1ChannelVoice(status: UInt8, data1: UInt8, data2: UInt8,
                                         group: UInt8 = 0) -> UInt32 {
        let g = UInt32(group & 0x0F)
        return (UInt32(0x2) << 28) | (g << 24)
            | (UInt32(status) << 16) | (UInt32(data1 & 0x7F) << 8) | UInt32(data2 & 0x7F)
    }

    public static func note1On(channel: UInt8, note: UInt8, velocity: UInt8, group: UInt8 = 0) -> UInt32 {
        midi1ChannelVoice(status: 0x90 | (channel & 0x0F), data1: note, data2: velocity, group: group)
    }

    public static func note1Off(channel: UInt8, note: UInt8, velocity: UInt8 = 0, group: UInt8 = 0) -> UInt32 {
        midi1ChannelVoice(status: 0x80 | (channel & 0x0F), data1: note, data2: velocity, group: group)
    }

    public static func controlChange1(channel: UInt8, index: UInt8, value: UInt8, group: UInt8 = 0) -> UInt32 {
        midi1ChannelVoice(status: 0xB0 | (channel & 0x0F), data1: index, data2: value, group: group)
    }

    /// 14-bit pitch bend (0…16383, centre 8192) as a MIDI 1.0 word (lsb, msb).
    public static func pitchBend1(channel: UInt8, value14: UInt16, group: UInt8 = 0) -> UInt32 {
        let v = Swift.min(value14, 0x3FFF)
        return midi1ChannelVoice(status: 0xE0 | (channel & 0x0F),
                                 data1: UInt8(v & 0x7F), data2: UInt8((v >> 7) & 0x7F), group: group)
    }

    // MARK: - System Real Time (message type 0x1 — one 32-bit word)

    /// Pack a System Real Time message (Clock 0xF8, Start 0xFA, Continue 0xFB, Stop 0xFC)
    /// into one 32-bit UMP word on `group`.
    /// Layout: [mt 0x1 | group | status | 0 | 0].
    ///
    /// ⚠️ WHY THIS CANNOT GO THROUGH `midi1ChannelVoice` (#300). That builder emits message
    /// type **0x2** and masks its data bytes to 7 bits. System Real Time is a different UMP
    /// message type entirely (**0x1**) and carries NO data bytes — sending 0xF8 through the
    /// channel-voice path produces a word a receiver decodes as a malformed channel message.
    /// `MIDIOutput.send(_:)` also rejects it before that: it requires 2…3 bytes and every
    /// real-time message is exactly ONE.
    ///
    /// Status is used verbatim, not masked: these have no channel nibble — 0xF8 IS the whole
    /// message. Masking with `& 0x0F` (the reflex from every builder above) would turn Clock
    /// into 0x08 and silently emit nothing a receiver recognises.
    public static func systemRealTime(status: UInt8, group: UInt8 = 0) -> UInt32 {
        (UInt32(0x1) << 28) | (UInt32(group & 0x0F) << 24) | (UInt32(status) << 16)
    }

    /// The System Real Time messages Echoel actually sends as a clock master.
    ///
    /// ⚠️ THREE CASES, NOT FIVE, AND THE OMISSIONS ARE DELIBERATE:
    ///   • **Continue (0xFB) is absent because nothing could send it.** `Transport.play()`
    ///     resets `position` to zero unconditionally, so every play edge in this app IS a
    ///     start from the top — Start (0xFA) is the correct message every time. Declaring
    ///     Continue would add a case with no producer, which is precisely the "lying
    ///     vocabulary" this repo keeps deleting. Add it together with a resume-from-position
    ///     transport, not before.
    ///   • Active Sensing (0xFE) — a keep-alive some gear mishandles; not a transport signal.
    ///   • System Reset (0xFF) — resets a receiver's entire state. Never on a clock.
    public enum RealTime: UInt8 {
        case clock = 0xF8   // 24 per quarter note
        case start = 0xFA   // begin at position zero
        case stop  = 0xFC
    }

    /// Seconds between two MIDI clock pulses at `bpm`, at the standard 24 PPQN.
    ///
    /// Pure and `nonisolated` so the timer path and the tests share ONE definition — the
    /// same reason `PatternEngine.swingGap` is a static. Returns nil for a tempo that cannot
    /// produce an interval (non-finite or ≤ 0), so a caller must decide rather than arm a
    /// timer with NaN. ⚠️ NaN never reaches a comparison here by accident: `bpm > 0` is FALSE
    /// for NaN, so the guard rejects it — the same positional property the repo's
    /// `clamped(to:)` note depends on.
    public static func clockInterval(bpm: Double, ppqn: Int = 24) -> Double? {
        guard bpm.isFinite, bpm > 0, ppqn > 0 else { return nil }
        return 60.0 / bpm / Double(ppqn)
    }

    // MARK: - MIDI 2.0 (message type 0x4 — two 32-bit words)

    /// Generic MIDI 2.0 channel-voice builder → (most-significant word, least-significant word).
    /// MSW: [mt 0x4 | group | opcode | channel | byte2 | byte3]; LSW: 32-bit data.
    public static func midi2ChannelVoice(opcode: UInt8, channel: UInt8,
                                         byte2: UInt8, byte3: UInt8, data: UInt32,
                                         group: UInt8 = 0) -> (UInt32, UInt32) {
        let msw = (UInt32(0x4) << 28) | (UInt32(group & 0x0F) << 24)
            | (UInt32(opcode & 0x0F) << 20) | (UInt32(channel & 0x0F) << 16)
            | (UInt32(byte2) << 8) | UInt32(byte3)
        return (msw, data)
    }

    /// MIDI 2.0 Note On (opcode 0x9): 16-bit velocity + optional 16-bit attribute.
    public static func note2On(channel: UInt8, note: UInt8, velocity16: UInt16,
                               attributeType: UInt8 = 0, attribute: UInt16 = 0,
                               group: UInt8 = 0) -> (UInt32, UInt32) {
        let data = (UInt32(velocity16) << 16) | UInt32(attribute)
        return midi2ChannelVoice(opcode: 0x9, channel: channel, byte2: note & 0x7F,
                                 byte3: attributeType, data: data, group: group)
    }

    /// MIDI 2.0 Note Off (opcode 0x8).
    public static func note2Off(channel: UInt8, note: UInt8, velocity16: UInt16 = 0,
                                attributeType: UInt8 = 0, attribute: UInt16 = 0,
                                group: UInt8 = 0) -> (UInt32, UInt32) {
        let data = (UInt32(velocity16) << 16) | UInt32(attribute)
        return midi2ChannelVoice(opcode: 0x8, channel: channel, byte2: note & 0x7F,
                                 byte3: attributeType, data: data, group: group)
    }

    /// MIDI 2.0 Control Change (opcode 0xB): 32-bit value.
    public static func controlChange2(channel: UInt8, index: UInt8, value32: UInt32,
                                      group: UInt8 = 0) -> (UInt32, UInt32) {
        midi2ChannelVoice(opcode: 0xB, channel: channel, byte2: index & 0x7F, byte3: 0,
                          data: value32, group: group)
    }

    /// MIDI 2.0 Channel Pressure (opcode 0xD): 32-bit value.
    public static func channelPressure2(channel: UInt8, value32: UInt32, group: UInt8 = 0) -> (UInt32, UInt32) {
        midi2ChannelVoice(opcode: 0xD, channel: channel, byte2: 0, byte3: 0, data: value32, group: group)
    }

    /// MIDI 2.0 per-channel Pitch Bend (opcode 0xE): 32-bit value, centre 0x8000_0000.
    public static func pitchBend2(channel: UInt8, value32: UInt32, group: UInt8 = 0) -> (UInt32, UInt32) {
        midi2ChannelVoice(opcode: 0xE, channel: channel, byte2: 0, byte3: 0, data: value32, group: group)
    }

    /// MIDI 2.0 PER-NOTE Pitch Bend (opcode 0x6): 32-bit value, centre 0x8000_0000.
    /// The per-voice Glide that MPE could only fake with a whole member channel.
    public static func perNotePitchBend2(channel: UInt8, note: UInt8, value32: UInt32,
                                         group: UInt8 = 0) -> (UInt32, UInt32) {
        midi2ChannelVoice(opcode: 0x6, channel: channel, byte2: note & 0x7F, byte3: 0,
                          data: value32, group: group)
    }

    /// MIDI 2.0 Assignable Per-Note Controller (opcode 0x1): 32-bit value per note +
    /// index (e.g. CC74 brightness / Slide as a true per-note stream).
    public static func perNoteController2(channel: UInt8, note: UInt8, index: UInt8, value32: UInt32,
                                          group: UInt8 = 0) -> (UInt32, UInt32) {
        midi2ChannelVoice(opcode: 0x1, channel: channel, byte2: note & 0x7F, byte3: index,
                          data: value32, group: group)
    }

    // MARK: - Resolution scaling (MMA min-center-max algorithm)

    /// Upscale an `fromBits`-bit value to `toBits` bits preserving the three anchors
    /// (0 → 0, centre → centre, max → max) per the MMA UMP scaling algorithm — the
    /// correct way to widen 7-bit velocity → 16-bit and 14-bit bend → 32-bit.
    public static func scaleUp(_ value: UInt32, fromBits: Int, toBits: Int) -> UInt32 {
        guard toBits > fromBits, fromBits > 0 else { return value }
        let scaleBits = toBits - fromBits
        let src = value & ((fromBits >= 32) ? 0xFFFF_FFFF : ((UInt32(1) << fromBits) - 1))
        var result = src << scaleBits
        let srcCenter = UInt32(1) << (fromBits - 1)
        if src <= srcCenter { return result }                 // lower half: pure shift
        let repeatBits = fromBits - 1
        let repeatMask = (UInt32(1) << repeatBits) - 1
        var repeatValue = src & repeatMask
        if scaleBits > repeatBits { repeatValue <<= (scaleBits - repeatBits) }
        else { repeatValue >>= (repeatBits - scaleBits) }
        while repeatValue != 0 {
            result |= repeatValue
            repeatValue >>= repeatBits
        }
        return result
    }

    /// Convenience: a 7-bit MIDI 1.0 value (velocity / CC) widened to 16 bits.
    public static func velocity7to16(_ v: UInt8) -> UInt16 { UInt16(scaleUp(UInt32(v & 0x7F), fromBits: 7, toBits: 16)) }

    /// Convenience: a 7-bit value widened to a full 32-bit MIDI 2.0 controller value.
    public static func cc7to32(_ v: UInt8) -> UInt32 { scaleUp(UInt32(v & 0x7F), fromBits: 7, toBits: 32) }

    /// Convenience: a 14-bit pitch-bend value widened to a 32-bit MIDI 2.0 bend
    /// (centre 8192 → 0x8000_0000).
    public static func bend14to32(_ v: UInt16) -> UInt32 { scaleUp(UInt32(v & 0x3FFF), fromBits: 14, toBits: 32) }
}
