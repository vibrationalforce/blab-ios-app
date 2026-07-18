//
//  BreathArp.swift
//  Echoelmusic — Sequencer (Scaler #4: breath-pattern generators)
//
//  Turns a chord into an ARPEGGIO the breath plays — the step that makes
//  EchoelBodyVibe a real instrument, not just a pulse trigger. Fully algorithmic
//  (no sampled arp library ⇒ IP-clean), pure and deterministic:
//
//    breath PHASE  → direction   (inhale climbs, exhale descends)
//    breath DEPTH  → density     (shallow = sparse hits, deep = every step)
//    chord         → the pitches walked
//
//  (Pulse→groove and motion-onset→strum accent are deliberately a later slice;
//  this core nails direction + density + the pitch walk.)
//
//  No audio, no state — a value function from (chord, breath) to the Notes to play
//  over one window. Unit-tested on every platform.
//

import Foundation

public enum BreathArp {

    /// Arp direction chosen by the breath phase: the rising half of the breath
    /// (inhale, phase < 0.5) climbs; the falling half (exhale) descends.
    public enum Direction: Equatable { case up, down }

    public static func direction(breathPhase: Float) -> Direction {
        let p = breathPhase.isFinite ? breathPhase : 0
        return p < 0.5 ? .up : .down
    }

    /// How many of `steps` grid cells fire, from breath depth: a shallow breath is
    /// sparse (but never silent — at least one hit), a deep breath fills the bar.
    public static func activeSteps(depth: Float, steps: Int) -> Int {
        guard steps > 0 else { return 0 }
        let d = clamp01(depth)
        return Swift.max(1, Int((d * Float(steps)).rounded()))
    }

    /// Whether step `i` (0-based, of `steps`) is one of `active` evenly-spread hits.
    /// The classic even distribution `(i * active) mod steps < active` — deterministic,
    /// no RNG, spreads the hits like a Euclidean rhythm.
    static func isActive(_ i: Int, active: Int, steps: Int) -> Bool {
        guard steps > 0, active > 0 else { return false }
        return ((i * active) % steps) < active
    }

    /// The arpeggio the breath plays over one window of `steps` grid cells.
    ///
    /// - `chordPitches`: the sounding chord (any order; out-of-range pitches dropped).
    /// - `steps`: grid cells in the window (e.g. 16 for one bar).
    /// - `breathPhase` / `breathDepth`: the live breath ([0..1] each).
    /// - `startTick` / `stepTicks`: where the window sits and how wide a cell is.
    ///
    /// Each active cell gets one note; the pitch walks the chord in `direction`
    /// order, wrapping within the chord (Alberti-style — octave-climb is a later
    /// refinement). Deterministic, with reproducible note ids folded from `startTick`.
    ///
    /// Slice 2 adds the body's GROOVE, both additive (default 0 ⇒ slice-1 output,
    /// byte-identical):
    /// - `motionAccent` (motion-onset → strum accent): lifts the velocity of the
    ///   downbeat cells (quarter-note positions) toward full, so a moved body hits
    ///   harder on the beat.
    /// - `swing` (pulse → groove): delays the off-16th cells (odd index) by up to one
    ///   cell, the classic swing push — a livelier body swings the pattern more.
    public static func pattern(
        chordPitches: [Int],
        steps: Int,
        breathPhase: Float,
        breathDepth: Float,
        startTick: Int = 0,
        stepTicks: Int = Note.ticksPerStep,
        velocity: Float = 0.8,
        motionAccent: Float = 0,
        swing: Float = 0
    ) -> [Note] {
        let pitches = chordPitches.filter { $0 >= 0 && $0 <= 127 }.sorted()
        guard !pitches.isEmpty, steps > 0 else { return [] }
        let vel = Swift.min(Swift.max(velocity.isFinite ? velocity : 0.8, 0.05), 1)
        let cellTicks = Swift.max(1, stepTicks)
        let order = direction(breathPhase: breathPhase) == .up ? pitches : pitches.reversed().map { $0 }
        let active = activeSteps(depth: breathDepth, steps: steps)
        let accent = clamp01(motionAccent)
        let swingTicks = Int(clamp01(swing) * Float(cellTicks))
        let beatCells = Swift.max(1, steps / 4)   // quarter-note grid

        var rng = SeededRNG(seed: UInt64(truncatingIfNeeded: startTick) ^ 0x42524541_54480000) // "BREATH"
        var out: [Note] = []
        var hit = 0
        for i in 0..<steps where isActive(i, active: active, steps: steps) {
            let pitch = order[hit % order.count]
            // Downbeat cells hit harder as motion rises (strum accent).
            let onBeat = i % beatCells == 0
            let noteVel = onBeat ? Swift.min(1, vel + accent * (1 - vel)) : vel
            // Off-16th cells swing late as the pulse quickens (groove).
            let offset = i % 2 == 1 ? swingTicks : 0
            out.append(Note(id: foldUUID(&rng), pitch: pitch,
                            startTick: Swift.max(0, startTick) + i * cellTicks + offset,
                            lengthTicks: cellTicks, velocity: noteVel))
            hit += 1
        }
        return out
    }

    // MARK: - Pure helpers

    static func clamp01(_ v: Float) -> Float {
        if v.isNaN { return 0 }
        return Swift.min(1, Swift.max(0, v))
    }

    /// Deterministic UUID from the RNG (same fold as `BioComposer.nextUUID`), so an
    /// arp is reproducible from its window.
    private static func foldUUID(_ rng: inout SeededRNG) -> UUID {
        let hi = rng.next()
        let lo = rng.next()
        func byte(_ v: UInt64, _ i: Int) -> UInt8 { UInt8((v >> (UInt64(i) * 8)) & 0xFF) }
        return UUID(uuid: (
            byte(hi, 7), byte(hi, 6), byte(hi, 5), byte(hi, 4),
            byte(hi, 3), byte(hi, 2), byte(hi, 1), byte(hi, 0),
            byte(lo, 7), byte(lo, 6), byte(lo, 5), byte(lo, 4),
            byte(lo, 3), byte(lo, 2), byte(lo, 1), byte(lo, 0)
        ))
    }
}
