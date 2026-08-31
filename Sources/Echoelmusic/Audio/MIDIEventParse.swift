// MIDIEventParse.swift
// Echoelmusic — Audio
//
// H10 (healing wave 2, task #30): the PURE half of MIDI input. The old
// MIDIInput parsed packets with `Mirror` reflection (allocation per packet on
// the realtime-adjacent CoreMIDI receive thread) and spawned one
// `Task { @MainActor }` PER EVENT — a dense MPE stream flooded the main
// executor (the 10.76.48 camera-freeze disease), and separate unstructured
// tasks carry NO FIFO guarantee, so a note-off could overtake its note-on
// (hung note under load).
//
// This file is Foundation-only (no CoreMIDI) so the word→event laws are
// Linux-CI-tested: MIDIEventParse maps UMP words to typed events, and
// MIDIInEventQueue is the lock-protected batch hand-off (RGBSampleQueue
// pattern) that guarantees FIFO order and AT MOST ONE main-actor drain task
// per burst. NSLock is fine here — the CoreMIDI receive thread is NOT the
// audio render thread (the no-locks law applies to render only).

import Foundation

/// One parsed incoming MIDI event (normalized floats, 0-based channel).
public enum MIDIInEvent: Equatable, Sendable {
    case noteOn(note: Int, velocity: Float, channel: Int)
    case noteOff(note: Int, channel: Int)
    case cc(number: Int, value: Float, channel: Int)
    case pitchBend(value: Float, channel: Int)
    /// ⭐ #939 — Channel Pressure (0xD0 / 0xD). MPE's PRESS dimension, and until now this
    /// receiver had no case for it: `MIDIEventParse` decoded four things in either protocol and
    /// 0xD0 fell to `default: return nil`, so a player leaning into a key sent bytes that were
    /// discarded one layer BELOW any wiring (`MIDIInput`'s header measured exactly that).
    ///
    /// ⚠️ THIS IS NOT "MPE SUPPORT" AND MUST NOT BE DESCRIBED AS SUCH. Zone detection (RPN 6,6)
    /// and master-vs-member channel disambiguation remain absent; `channel` is carried here and
    /// read by nobody. One dimension of three now reaches a voice — the other two (`.slide`,
    /// `.airCC`) still land in a single `break`, which `TheMPEDimensionsReachNoVoiceTests`
    /// pins. Store text, website and `ContentPipeline/CLAIMS.md` stay untouched.
    case channelPressure(value: Float, channel: Int)
}

/// Pure UMP word(s) → event mapping. Behavior-identical to the pre-H10 inline
/// parsing (verified case-by-case in tests). MIDI-1.0 bend note: Swift parses
/// `lsb | (msb << 7) - 8192` as `(lsb | (msb << 7)) - 8192` (`|` and `-` share
/// AdditionPrecedence, left-associative) — the standard 14-bit formula; the
/// other grouping would be equal anyway (the OR operands never share set bits),
/// and the mixed-LSB test pins it.
public enum MIDIEventParse {

    /// `word0` is the packet's first UMP word; `word1` its second (MIDI 2.0
    /// payloads) or nil. Unknown/unsupported messages → nil (dropped, as before).
    public static func event(word0: UInt32, word1: UInt32?) -> MIDIInEvent? {
        let messageType = (word0 >> 28) & 0xF
        let channel = Int((word0 >> 16) & 0xF)

        switch messageType {
        case 0x2: // MIDI 1.0 Channel Voice (legacy)
            let status = (word0 >> 16) & 0xFF
            let data1 = Int((word0 >> 8) & 0x7F)
            let data2raw = word0 & 0x7F
            let data2 = Float(data2raw) / 127.0
            switch status & 0xF0 {
            case 0x90: // Note On (velocity 0 = off, MIDI law)
                return data2raw > 0
                    ? .noteOn(note: data1, velocity: data2, channel: channel)
                    : .noteOff(note: data1, channel: channel)
            case 0x80:
                return .noteOff(note: data1, channel: channel)
            case 0xB0:
                return .cc(number: data1, value: data2, channel: channel)
            case 0xD0:
                // ⚠️ CHANNEL PRESSURE IS A TWO-BYTE MESSAGE — status plus ONE data byte — so
                // the value is `data1`, NOT `data2`. Every other case here reads its level out
                // of `data2` (the SECOND data byte), and copying that shape would have read the
                // running-status filler as pressure: silent, always-0, and indistinguishable
                // from a player who is not pressing.
                return .channelPressure(value: Float(data1) / 127.0, channel: channel)
            case 0xE0:
                let bendValue = Float(data1 | (Int(word0 & 0x7F) << 7) - 8192) / 8192.0
                return .pitchBend(value: bendValue, channel: channel)
            default:
                return nil
            }

        case 0x4: // MIDI 2.0 Channel Voice
            guard let word1 else { return nil }
            let statusNibble = (word0 >> 20) & 0xF
            switch statusNibble {
            case 0x9: // Note On (16-bit velocity in word1's high half)
                let note = Int((word0 >> 8) & 0x7F)
                return .noteOn(note: note,
                               velocity: Float(word1 >> 16) / 65535.0,
                               channel: channel)
            case 0x8:
                return .noteOff(note: Int((word0 >> 8) & 0x7F), channel: channel)
            case 0xB: // CC (32-bit value)
                return .cc(number: Int((word0 >> 8) & 0x7F),
                           value: Float(word1) / Float(UInt32.max),
                           channel: channel)
            case 0xD: // Channel Pressure (32-bit value, like CC above)
                return .channelPressure(value: Float(word1) / Float(UInt32.max),
                                        channel: channel)
            case 0xE: // Pitch Bend (signed 32-bit)
                return .pitchBend(value: Float(Int32(bitPattern: word1)) / Float(Int32.max),
                                  channel: channel)
            default:
                return nil
            }

        default:
            return nil
        }
    }
}

/// The CoreMIDI-thread → main-actor batch hand-off. The receive thread pushes
/// parsed events under a short lock; `push` returns true exactly ONCE per
/// burst (the caller then spawns the single drain task). The drain empties
/// everything in FIFO order and re-arms. Overflow beyond `capacity` drops the
/// NEWEST events and counts them honestly (reported at the next drain) —
/// never blocks, never reorders.
public final class MIDIInEventQueue: @unchecked Sendable {

    public static let capacity = 512

    private let lock = NSLock()
    private var events: [MIDIInEvent] = []
    private var drainScheduled = false
    private var dropped = 0

    public init() {}

    /// Enqueue from the receive thread. Returns true when the caller must
    /// schedule the ONE drain for this burst (i.e. none is pending yet).
    public func push(_ event: MIDIInEvent) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if events.count < Self.capacity {
            events.append(event)
        } else {
            dropped &+= 1
        }
        if drainScheduled { return false }
        drainScheduled = true
        return true
    }

    /// Take EVERYTHING pending (FIFO) + the overflow count, and re-arm so the
    /// next push schedules a fresh drain.
    public func drain() -> (events: [MIDIInEvent], dropped: Int) {
        lock.lock(); defer { lock.unlock() }
        let out = events
        let lost = dropped
        events.removeAll(keepingCapacity: true)
        // `out` shares the buffer (CoW), so the removeAll above detaches —
        // re-reserve so the next burst appends without a growth allocation.
        events.reserveCapacity(Self.capacity)
        dropped = 0
        drainScheduled = false
        return (out, lost)
    }
}
