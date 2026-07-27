// RollNoteOps.swift
// Echoel — pure selection operators for the piano roll (R1, PLAN_ROLL_PRO.md).
// Foundation-only static funcs on [Note]: deterministic, unit-testable without
// SwiftUI or a transport. All time math is PPQ ticks inside the roll's ONE
// fixed 16-step bar (16 × 120 = 1920 ticks); every result is clamped into that
// window (no tick < 0, no end > barTicks). Ops NEVER touch role/operators/mpe —
// a transformed note keeps its id (Echo's copies are the one exception: they
// are NEW notes, so they get fresh ids).
//
// The UI applies these through `PianoRollModel.applyOp(ids:_:)` so every op is
// ONE undoable edit, exactly like Quantize.

import Foundation

public enum RollNoteOps {

    /// One 4/4 bar of the roll's fixed 16-step grid, in PPQ ticks (= 1920).
    public static let barTicks = 16 * Note.ticksPerStep

    /// Musical velocity floor shared with BioComposer's humanize window — an
    /// echo tail decays toward "very quiet", never to a dead 0-velocity note.
    static let minVelocity: Float = 0.05

    // MARK: - Time ops

    /// Retrograde within the bar: mirror each note's TIME (including its length,
    /// tick-exact) around the bar — the note that ENDED at tick e now STARTS at
    /// `barTicks − e`. Length is preserved, so `reverse(reverse(x)) == x` for
    /// any in-bar input. An out-of-contract end past the bar clamps to it first.
    public static func reverse(_ notes: [Note]) -> [Note] {
        notes.map { n in
            var m = n
            m.startTick = max(0, barTicks - min(n.endTick, barTicks))
            return m
        }
    }

    /// Legato: extend each note to the START of the next note in the same
    /// selection (the next strictly-later start tick — a chord's notes share
    /// their next start), and the last note(s) to the bar end. Pitch and start
    /// are untouched; only lengths grow/shrink to close every gap.
    public static func legato(_ notes: [Note]) -> [Note] {
        notes.map { n in
            var m = n
            let nextStart = notes.map(\.startTick).filter { $0 > n.startTick }.min() ?? barTicks
            m.lengthTicks = max(1, min(nextStart, barTicks) - min(n.startTick, barTicks - 1))
            return m
        }
    }

    /// Double the TIME VALUES (Ableton's ×2 button): start and length × 2 — the
    /// selection stretches to twice its span, i.e. plays at HALF speed inside
    /// the fixed 1-bar loop. Notes whose doubled start lands at/past the bar
    /// end FALL OUT the back and are DROPPED (documented contract — the bar is
    /// fixed, there is no bar 2 to spill into); a surviving note that straddles
    /// the bar end keeps its onset and its tail clamps to the bar end.
    /// NOT an inverse of `halfTime`: dropping + clamping + halfTime's integer
    /// floor make `halfTime(doubleTime(x))` ≠ `x` in general.
    public static func doubleTime(_ notes: [Note]) -> [Note] {
        notes.compactMap { n in
            let s = n.startTick * 2
            guard s < barTicks else { return nil }
            var m = n
            m.startTick = s
            m.lengthTicks = max(1, min(n.lengthTicks * 2, barTicks - s))
            return m
        }
    }

    /// Halve the TIME VALUES (Ableton's :2 button): start and length ÷ 2 — the
    /// selection compresses into half its span (double-speed feel). Lengths
    /// floor at 1 tick; every end is clamped to the bar end ("klemmt ans
    /// Taktende" — vacuous for in-bar input, a hard guard for anything else).
    /// Integer division floors, so `doubleTime(halfTime(x))` ≠ `x` in general.
    public static func halfTime(_ notes: [Note]) -> [Note] {
        notes.map { n in
            var m = n
            m.startTick = min(n.startTick / 2, barTicks - 1)
            m.lengthTicks = max(1, min(max(1, n.lengthTicks / 2), barTicks - m.startTick))
            return m
        }
    }

    /// Echo (FL flam/roll family): for each note, up to `times` decaying copies
    /// at the note's OWN length as the interval — copy k starts at
    /// `start + k·length` with velocity `v·decay^k` (clamped to the musical
    /// [0.05, 1] window). Purely ADDITIVE: originals are untouched; copies
    /// starting at/past the bar end are dropped and a straddling copy's tail
    /// clamps to the bar end. Copies get fresh ids (they are new notes), so
    /// determinism covers every musical field, not the ids.
    public static func echo(_ notes: [Note], times: Int, decay: Float) -> [Note] {
        guard times > 0 else { return notes }
        let d = decay.clamped(to: 0...1)                  // NaN-safe (see Note's init)
        var out = notes
        for n in notes {
            var vel = n.velocity
            for k in 1...times {
                let s = n.startTick + k * n.lengthTicks
                guard s < barTicks else { break }
                // NaN-safe: `c.velocity = vel` below writes the public `var`, which
                // BYPASSES `Note`'s clamping init — so this is the only guard on the
                // path from here into a saved note (and thence to `Int(v * 127)`).
                vel = (vel * d).clamped(to: minVelocity...1)
                var c = n
                c.id = UUID()
                c.startTick = s
                c.lengthTicks = max(1, min(n.lengthTicks, barTicks - s))
                c.velocity = vel
                out.append(c)
            }
        }
        return out
    }

    // MARK: - Pitch ops

    /// Invert PITCH around the selection's own centre: with `lo`/`hi` the
    /// selection's lowest/highest pitch, each pitch p maps to `lo + hi − p`
    /// (integer-exact — no /2 rounding), which swaps lo↔hi and preserves the
    /// centre, so `invert(invert(x)) == x` whenever no clamping fires. The
    /// result is clamped to the roll's `[lowPitch, highPitch]` window (a clamp
    /// breaks the involution — documented, tested with in-window material).
    public static func invertPitch(_ notes: [Note], lowPitch: Int, highPitch: Int) -> [Note] {
        guard let lo = notes.map(\.pitch).min(),
              let hi = notes.map(\.pitch).max() else { return notes }
        let sum = lo + hi
        return notes.map { n in
            var m = n
            m.pitch = min(max(sum - n.pitch, lowPitch), highPitch)
            return m
        }
    }

    /// Snap ONE pitch to the nearest in-key tone. Ties resolve DOWNWARD
    /// (`MusicalKey.quantize` searches below first), then the result is
    /// octave-folded into the roll's window so it stays in scale AND on
    /// screen (a plain clamp could land out of scale). Idempotent for an
    /// in-key, in-window pitch.
    public static func snapPitch(_ pitch: Int, key: MusicalKey,
                                 lowPitch: Int, highPitch: Int) -> Int {
        var p = key.quantize(pitch)
        while p < lowPitch { p += 12 }
        while p > highPitch { p -= 12 }
        return min(max(p, lowPitch), highPitch)   // degenerate-window guard
    }

    /// Snap every note to the nearest in-key tone (see `snapPitch`).
    public static func snapToScale(_ notes: [Note], key: MusicalKey,
                                   lowPitch: Int, highPitch: Int) -> [Note] {
        notes.map { n in
            var m = n
            m.pitch = snapPitch(n.pitch, key: key, lowPitch: lowPitch, highPitch: highPitch)
            return m
        }
    }

    // MARK: - Velocity ops

    /// Linear velocity ramp over the selection's TIME ORDER (start tick, then
    /// pitch, then id — a total order, so the ramp is fully deterministic).
    /// First note gets `from`, last gets `to`; a single note gets `from`.
    /// Values clamp to [0, 1]. Pitch/time untouched.
    public static func velocityRamp(_ notes: [Note], from: Float, to: Float) -> [Note] {
        let order = notes.sorted { a, b in
            if a.startTick != b.startTick { return a.startTick < b.startTick }
            if a.pitch != b.pitch { return a.pitch < b.pitch }
            return a.id.uuidString < b.id.uuidString
        }
        let denom = max(1, order.count - 1)
        var byID: [UUID: Float] = [:]
        for (i, n) in order.enumerated() {
            let t = Float(i) / Float(denom)
            byID[n.id] = min(max(from + (to - from) * t, 0), 1)
        }
        return notes.map { n in
            var m = n
            m.velocity = byID[n.id] ?? n.velocity
            return m
        }
    }

    // MARK: - Bio-Humanize seed

    /// Order-independent FNV-1a hash of the notes' MUSICAL content (pitch,
    /// start, length, velocity bits — ids excluded) — the deterministic seed
    /// for the roll's Bio-Humanize op: the same selection in the same state
    /// humanizes identically, and any change (including a previous humanize
    /// pass, which moved the velocities) re-seeds the jitter stream.
    public static func stableSeed(for notes: [Note]) -> UInt64 {
        let ordered = notes.sorted { a, b in
            if a.startTick != b.startTick { return a.startTick < b.startTick }
            if a.pitch != b.pitch { return a.pitch < b.pitch }
            if a.lengthTicks != b.lengthTicks { return a.lengthTicks < b.lengthTicks }
            return a.velocity.bitPattern < b.velocity.bitPattern
        }
        var h: UInt64 = 0xcbf2_9ce4_8422_2325          // FNV offset basis
        func mix(_ x: UInt64) {
            h ^= x
            h = h &* 0x0000_0100_0000_01b3             // FNV prime
        }
        for n in ordered {
            mix(UInt64(bitPattern: Int64(n.pitch)))
            mix(UInt64(bitPattern: Int64(n.startTick)))
            mix(UInt64(bitPattern: Int64(n.lengthTicks)))
            mix(UInt64(n.velocity.bitPattern))
        }
        return h
    }
}
