// MPEExpression.swift
// Echoel — body → ROLI-style "5D" MPE expression, as a PURE, unit-tested value type
// (no CoreMIDI, so it builds + tests everywhere). The body is the controller: the
// three CONTINUOUS MPE per-note dimensions are driven by bio —
//   • Slide (CC74, brightness)  ← coherence   (servo: coherent = clearer/brighter)
//   • Press (channel pressure)  ← breath depth (inhale swells the note)
//   • Glide (pitch bend)        ← HRV          (a small, living pitch drift)
// plus Strike (note-on velocity) and Lift (note-off velocity) carried by the note
// events themselves. This is the encoder/mapping core; wiring it into the CoreMIDI
// MPE output path (MIDIOutput) is a separate, iOS-gated slice.

import Foundation

public struct MPEExpression: Equatable, Sendable {
    /// Slide / timbre, MIDI CC74 value 0…127.
    public var slideCC74: UInt8
    /// Press / channel pressure (aftertouch) 0…127.
    public var pressure: UInt8
    /// Glide / per-note pitch bend, normalized −1…+1 (maps onto the MPE bend range).
    public var bend: Float

    public init(slideCC74: UInt8, pressure: UInt8, bend: Float) {
        self.slideCC74 = slideCC74
        self.pressure = pressure
        self.bend = Swift.max(-1, Swift.min(1, bend))
    }

    static func clamp01(_ x: Float) -> Float { Swift.min(1, Swift.max(0, x)) }
    private static func u7(_ x: Float) -> UInt8 { UInt8(Swift.max(0, Swift.min(127, (x * 127).rounded()))) }

    /// Map a bio snapshot to continuous 5D expression. HRV drives only a SMALL
    /// living drift: `bendCents` of audible bend within the synth's `bendRangeSemitones`
    /// (MPE default ±48), so the pitch stays musical, never a wild bend.
    public static func from(coherence: Float, breathDepth: Float, hrvNormalized: Float,
                            bendCents: Float = 50, bendRangeSemitones: Float = 48) -> MPEExpression {
        let slide = u7(clamp01(coherence))
        let press = u7(clamp01(breathDepth))
        let range = Swift.max(1, bendRangeSemitones)
        let drift = (clamp01(hrvNormalized) * 2 - 1) * (bendCents / 100) / range   // −1…1, tiny
        return MPEExpression(slideCC74: slide, pressure: press, bend: drift)
    }

    /// 14-bit pitch-bend bytes (lsb, msb) for a normalized −1…+1 value. Centre (0) →
    /// 8192 = (lsb 0, msb 64); −1 → 0; +1 → 16383.
    public static func pitchBend14(_ normalized: Float) -> (lsb: UInt8, msb: UInt8) {
        let clamped = Swift.max(-1, Swift.min(1, normalized))
        let value = Swift.max(0, Swift.min(16383, Int(((Double(clamped) + 1) * 0.5 * 16383).rounded())))
        return (UInt8(value & 0x7F), UInt8((value >> 7) & 0x7F))
    }

    /// MPE lower-zone MEMBER channel (1-based 2…16) for the n-th simultaneous note,
    /// round-robin so each voice's per-note bend/pressure/CC74 don't collide. The
    /// Master/Manager channel is 1. `memberCount` is the zone size (default 15 = full).
    public static func memberChannel(noteIndex: Int, memberCount: Int = 15) -> Int {
        let m = Swift.max(1, Swift.min(15, memberCount))
        return 2 + (Swift.max(0, noteIndex) % m)        // 2 … (1 + m)
    }
}
