//
//  ArpFigure.swift
//  Echoelmusic — Sequencer
//
//  THE ARP'S ORDER WALK (founder 2026-07-29: *"Vielleicht ist der arp auch eine eigene
//  Kategorie und könnte ein komplexes bedienelement werden"*).
//
//  ⛔ WHY THIS EXISTS AS A NEW CORE RATHER THAN A CONTROL ON THE EXISTING ARP, because that is
//  the decision a reader will want to overturn first. `BreathArp` already walks a chord, and its
//  PATTERN half is genuinely doorless: `BreathArp.pattern`'s one caller is
//  `PianoRollModel.stampArp`, whose one call site sits inside `PianoRollView` — and
//  `PianoRollView` is instantiated NOWHERE since the founder removed the note editor (#178). So
//  the obvious move is to re-door `BreathArp`. It does not work, and the reason is structural
//  rather than a matter of effort:
//
//  ⚠️ SAY "PATTERN HALF", NOT "BreathArp", and the distinction is not pedantry — an earlier draft
//  of this paragraph said `BreathArp`'s ONE production caller was `stampArp`, which is FALSE:
//  `BreathArp.isActive` is live and reachable at `FieldAutoPlay.swift:310`, on the 60 Hz self-play
//  path. A session reading the wrong version would have concluded the whole type is dead and
//  deleted it, taking the Field's Euclidean density rule with it. `BreathArp` is not dead; one of
//  its two halves has no door.
//
//    `PianoRollModel.trigger` selects notes by `$0.startStep == step`, and `Note.startStep` is a
//    ROUNDING view over ticks (`Note.swift:173-176`), with `lengthSteps` rounding UP to at least
//    1. On that path the finest rate is 1/16 = 120 ticks. A swing below half a cell is quantised
//    away and above it becomes a whole-step jump; two arp notes 60 ticks apart land on the SAME
//    step (a flam, not a ratchet); a sub-step gate length cannot be expressed at all.
//
//  So any 1/32, triplet or gate control written into that path would be a LYING CONTROL — the
//  class of defect this repo has already paid for four times (#164, #227). The sub-step clock
//  the founder's ask needs already exists and is reachable: `TouchInstrumentUIView.autoPlayTick`
//  polls `Transport.currentTick()` on a 60 Hz display link and resolves cells through
//  `FieldAutoPlay.cell(forTick:ticksPerCell:)`, whose grid vocabulary includes both triplet
//  divisions (`TouchQuantizer.Grid`, 480/240/160/120/80 ticks).
//
//  Hence the split: this type answers ONLY "which chord tone, in which octave, at walk position
//  i". It does not know about keys, pitches, surfaces, ticks or audio. `BreathArp` keeps its own
//  job (breath phase → direction, breath depth → density) and is not touched.
//
//  Pure Foundation, deterministic from `(index, chord, octaves, order, seed)`, no state, no
//  clock: the caller owns the tick. Same discipline as `FieldAutoPlay`, and for the same reason —
//  the shape of a walk is exactly the kind of thing that reads correctly in code and sounds like
//  a stuck note on a device, so it has to be assertable without an Apple UI stack.
//
//  ⚠️ NOT YET REACHABLE, and this file does not pretend otherwise: nothing in `Sources/` calls
//  either half. The walk (S1) and the surface projection (S2, `surfacePoint`) are both here; the
//  `FieldAutoPlay.Motion` case, the driver argument, the storage keys and the panel are still
//  separate slices (#220 S3…S6). A core with no door is honest as long as it is written down as
//  one — and this line is the only thing keeping "two shipped, unused functions" from reading as
//  a feature.
//

import Foundation

/// The order in which an arpeggio walks the tones of a chord.
public enum ArpFigure {

    /// Which way the walk moves through the chord.
    ///
    /// Six, and deliberately few: a menu of twelve subtly different orders is the "more options
    /// that sound the same" failure this project has already hit twice (#81, #125). Each of
    /// these is audibly a different figure, not a different flavour of the same one.
    public enum Order: String, CaseIterable, Sendable, Codable {
        /// Low to high, then jump back to the bottom. The classic ascending run.
        case up
        /// The mirror of `up`.
        case down
        /// Up and back down WITHOUT repeating the turnaround note — the continuous one.
        case upDown
        /// The mirror of `upDown`: down first, then back up.
        case downUp
        /// The chord's own order, exactly as it was handed in. How an inversion or a
        /// deliberately voiced chord keeps its shape instead of being sorted flat.
        case asPlayed
        /// A seeded shuffle, re-drawn once per cycle.
        ///
        /// ⚠️ SAY WHAT IT IS RATHER THAN "random": every tone still sounds exactly ONCE per
        /// cycle, in a scrambled order that changes from cycle to cycle. It is not a dice roll
        /// per step — that would repeat some tones and drop others, which the ear hears as
        /// stumbling rather than as an irregular figure. (Same lesson `FieldAutoPlay.fires`
        /// records for density: an even spread reads as a rate, a roll at the same average
        /// reads as a mistake.)
        case random
    }

    /// One position in the walk: which chord tone, lifted by how many octaves.
    ///
    /// `degreeIndex` is a SCALE-degree index, not a semitone and not an index into the chord
    /// array — so `[0, 2, 4]` is the triad in whatever scale the caller is in, and stays a triad
    /// in a pentatonic or maqam scale where the semitone distances differ. Turning it into a
    /// pitch is the next slice's job and needs the key; that is exactly why it is not done here.
    ///
    /// `Hashable` rather than only `Equatable` so a test can put a whole cycle in a `Set` and
    /// assert coverage — the walk-completeness property is the one worth pinning and it is
    /// awkward to state without one.
    public struct Step: Hashable, Sendable {
        public var degreeIndex: Int
        public var octaveOffset: Int

        public init(degreeIndex: Int, octaveOffset: Int) {
            self.degreeIndex = degreeIndex
            self.octaveOffset = octaveOffset
        }
    }

    /// Highest octave span the walk may use.
    ///
    /// 3 to match the play surface's three registers (`TouchPitchMap.octaveBands` = `[3, 4, 5]`).
    ///
    /// ⚠️ A DESIGN CHOICE, NOT A PHYSICAL LIMIT, and the first version of this comment claimed the
    /// stronger thing — that a fourth octave "could not sound". It can. `octaveBands` picks the
    /// BASE octave from the finger's y position; `Step.octaveOffset` is an offset on top of that,
    /// and `MusicalKey.degree` applies no ceiling (only `Note` clamps, at MIDI 127). So octaves 6
    /// and 7 sound perfectly well. What 3 buys is that the arp stays inside the register the
    /// surface itself spans, and the actual saturation against the top band belongs to the S2
    /// projection. Overstating a bound as impossible is how a later slice skips the clamp that
    /// really is needed.
    public static let maxOctaves = 3

    /// Most chord tones the walk will carry.
    ///
    /// A chord is not a scale: twelve is one full chromatic octave, past which "chord tone" has
    /// stopped meaning anything. Octave spread is a separate dial, so the largest musically
    /// meaningful input is a thirteenth chord — seven tones.
    ///
    /// ⚠️ NAMED `maxChordTones` AND NOT `maxVoices` ON PURPOSE: `FieldAutoPlay.maxVoices` = 8 in
    /// this same directory means something else entirely (simultaneous sounding points), and S2
    /// wires the two types together. Two different numbers under one name in one folder is a trap.
    ///
    /// ⚠️ AND THE REASON IS NOT WHAT I FIRST WROTE. The claim was that this bounds per-call work
    /// because the eventual caller is a 60 Hz display link. It does not: `sanitize` iterates the
    /// ENTIRE input array whatever the cap, so a 500-element decoded array still costs 500
    /// iterations per frame. The cap bounds the `permutation` allocation and the cycle length —
    /// which at ≤ 36 was never a 60 Hz concern in the first place. The honest reason to keep it is
    /// that a decoded array must not size an allocation, and that a "chord" of 500 tones is data
    /// corruption rather than a musical request.
    public static let maxChordTones = 12

    // MARK: - The walk

    /// The chord tone at walk position `index`, or `nil` when there is no chord to walk.
    ///
    /// ⛔ RETURNS `nil` RATHER THAN A SILENT DEFAULT for an empty chord, and that is the whole
    /// reason it is optional. A generator that substitutes "the root" for "nothing to play"
    /// sounds like a stuck single note and reads, on a device, exactly like a broken arp — the
    /// caller must decide to stay silent, and it can only decide that if it is told.
    ///
    /// - Parameters:
    ///   - index: Position in the walk. May be negative (a caller resolving a cell from a
    ///     transport tick before zero) and wraps by flooring, so `-1` is the last position of
    ///     the previous cycle rather than a crash or a mirrored index.
    ///   - chordDegrees: Scale-degree indices. Negatives are dropped, duplicates collapse to
    ///     their first occurrence, and the first `maxChordTones` survive.
    ///   - octaves: Octave span, clamped to `1...maxOctaves`.
    ///   - order: How the walk moves.
    ///   - seed: Consumed by `.random` ONLY. The other five orders are shapes, not draws, and
    ///     must be reproducible without it.
    public static func step(
        atIndex index: Int,
        chordDegrees: [Int],
        octaves: Int,
        order: Order,
        seed: UInt64
    ) -> Step? {
        let voices = sanitize(chordDegrees)
        guard !voices.isEmpty else { return nil }

        let span = Swift.min(Swift.max(octaves, 1), maxOctaves)
        let cycle = voices.count * span          // distinct positions, ≥ 1

        // Ascending is the canonical mapping; every order is a permutation of ITS positions.
        // Doing it this way is what makes `.down` walk the top octave downwards before dropping
        // to the next one — the musically expected shape, and the one an
        // octave-outside-the-degree-loop implementation gets wrong.
        //
        // The sort lives INSIDE `ascendingTone` rather than above the switch so `.asPlayed`, the
        // one order that must not sort, does not pay for it. Small, but this file argues about
        // per-call cost elsewhere and should not then allocate a sorted copy it never reads.
        func tone(_ position: Int, from pool: [Int]) -> Step {
            Step(degreeIndex: pool[position % pool.count],
                 octaveOffset: position / pool.count)
        }
        func ascendingTone(_ position: Int) -> Step { tone(position, from: voices.sorted()) }

        switch order {
        case .up:
            return ascendingTone(floorMod(index, cycle))

        case .down:
            return ascendingTone(cycle - 1 - floorMod(index, cycle))

        case .asPlayed:
            return tone(floorMod(index, cycle), from: voices)

        case .upDown, .downUp:
            // 2·cycle − 2 so neither end is played twice in a row. `cycle == 1` degenerates to
            // 0, which would be a division by zero — one tone has no turnaround to avoid.
            let length = cycle > 1 ? 2 * cycle - 2 : 1
            let j = floorMod(index, length)
            let up = j < cycle ? j : 2 * cycle - 2 - j
            return ascendingTone(order == .upDown ? up : cycle - 1 - up)

        case .random:
            // Re-derived from the CYCLE index rather than carried in state, for the reason
            // `FieldAutoPlay.travel` states about its drift: this is a pure function of its
            // arguments, so a caller may ask for any position in any order — a scrub, a test, a
            // re-render — and must get the same answer. A stateful shuffle would silently
            // depend on call order.
            let which = floorDiv(index, cycle)
            let position = floorMod(index, cycle)
            return ascendingTone(permutation(count: cycle, seed: seed, cycleIndex: which)[position])
        }
    }

    // MARK: - Projection onto the play surface

    /// Where on the play surface a walk position must be touched for it to sound.
    ///
    /// Returns a normalized point in the same coordinates a FINGER uses — `x` 0…1 left→right,
    /// `y` 0…1 bottom→top — so the caller feeds it into the one mapping that already ships
    /// (`TouchPitchMap.pitch(normX:normY:key:)`, `TouchInstrumentView.swift:44-53`) and the arp
    /// is quantised into the take's key by exactly the same code as a played note. No second
    /// pitch path, so no second way to produce a wrong note.
    ///
    /// ⛔ WHY x LANDS IN THE MIDDLE OF THE DEGREE CELL, and this is the whole reason this
    /// function exists instead of a one-line division at the call site: the consumer computes
    /// its degree as `Int(x * n)` — it FLOORS. Handing it the cell's left EDGE (`d / n`) puts
    /// the value exactly on a boundary where a representation error of one ulp decides between
    /// degree `d` and degree `d − 1`, i.e. a wrong note some of the time and a correct one the
    /// rest — the least debuggable class of musical defect there is. The centre `(d + 0.5) / n`
    /// is half a cell from either boundary, so no accumulation of float error can move it.
    ///
    /// ⚠️ `bandCount` IS THE CONSUMER'S BAND COUNT, passed in rather than read.
    /// `TouchPitchMap.octaveBands` has three entries today (`TouchInstrumentView.swift:39`), but
    /// importing it here would drag `Studio/` into a file whose whole point is that it is pure
    /// Foundation. The test pins the two together against the real `TouchPitchMap` instead —
    /// which is the stronger check anyway, because it fails if EITHER side moves.
    ///
    /// ⚠️ THE TOP BAND SATURATES, and a caller that ignores this will hear it. The surface spans
    /// `bandCount` registers and nothing else; `y` cannot express a fourth one, because the
    /// consumer clamps the band it derives (`min(octaveBands.count - 1, …)`). So a walk started
    /// at `band` with a span that reaches past the top plays its highest octaves TWICE at the
    /// top instead of rising — audible as an arp that hits a ceiling. This function saturates
    /// rather than folding downward (a fold would sound like a mistake, a ceiling sounds like a
    /// range limit), and it deliberately does NOT quietly re-base the walk lower: moving the
    /// register out from under the player's own finger is the worse surprise. The caller that
    /// wants every octave audible passes a `band` with `band + octaves - 1 < bandCount`.
    ///
    /// - Parameters:
    ///   - step: A position from `step(atIndex:…)`, or any `Step` a caller built itself.
    ///     `degreeIndex` values at or beyond `degreesPerOctave` — a ninth, an eleventh — fold
    ///     into the octave lift rather than running off the right edge of the surface, and
    ///     negative ones fold downward the same way.
    ///   - degreesPerOctave: Scale degrees per octave (`MusicalKey.degreesPerOctave`). Values
    ///     below 1 are treated as 1; a scale with no notes is data corruption, not a request.
    ///   - bandCount: Octave bands the surface spans. Below 1 is treated as 1.
    ///   - band: The base band the walk starts in, 0 = lowest.
    public static func surfacePoint(
        _ step: Step,
        degreesPerOctave: Int,
        bandCount: Int,
        band: Int
    ) -> (x: Double, y: Double) {
        let degrees = Swift.max(1, degreesPerOctave)
        let bands = Swift.max(1, bandCount)

        // A degree past the octave is an octave lift, not a position further right. `floorDiv`
        // and `floorMod` are the same pair the walk uses, so degree 7 in a seven-note scale —
        // the ninth, counting the root as 1 — becomes "the ROOT, one octave up" in both places.
        // (It is the root and not the second: degree 7 is the eighth degree, i.e. the octave.)
        let carry = floorDiv(step.degreeIndex, degrees)
        let degreeInOctave = floorMod(step.degreeIndex, degrees)

        // Saturating, because `degreeIndex` may come from decoded data: `floorDiv(Int.max, 1)`
        // is `Int.max`, and `Int.max + band` would trap. The band is clamped to the surface
        // immediately afterwards anyway, so saturation loses nothing real.
        let lifted = saturatingSum(saturatingSum(band, step.octaveOffset), carry)
        let targetBand = Swift.min(bands - 1, Swift.max(0, lifted))

        return (x: (Double(degreeInOctave) + 0.5) / Double(degrees),
                y: (Double(targetBand) + 0.5) / Double(bands))
    }

    // MARK: - Pure pieces

    /// Drops negative degrees, collapses duplicates to their first occurrence (so `.asPlayed`
    /// keeps the voicing it was handed) and caps the result at `maxChordTones`.
    ///
    /// Duplicates have to go, and not for tidiness: with them, one chord tone would sound twice
    /// per cycle while the cycle length still counted it twice — the walk would stutter on that
    /// note and the coverage property below would be false.
    static func sanitize(_ chordDegrees: [Int]) -> [Int] {
        var seen = Set<Int>()
        var out: [Int] = []
        out.reserveCapacity(Swift.min(chordDegrees.count, maxChordTones))
        for degree in chordDegrees where degree >= 0 {
            guard seen.insert(degree).inserted else { continue }
            out.append(degree)
            if out.count == maxChordTones { break }
        }
        return out
    }

    /// A seeded permutation of `0..<count` for one cycle. Fisher–Yates with `SeededRNG`, keyed
    /// on the cycle index so consecutive cycles scramble differently and the same cycle always
    /// scrambles the same way.
    static func permutation(count: Int, seed: UInt64, cycleIndex: Int) -> [Int] {
        guard count > 1 else { return count == 1 ? [0] : [] }
        var rng = SeededRNG(seed: seed
                            &+ UInt64(bitPattern: Int64(cycleIndex)) &* 0x9E3779B97F4A7C15
                            &+ 0x41525000_00000000)                       // "ARP"
        var out = Array(0..<count)
        var i = count - 1
        while i > 0 {
            let j = Int(rng.next() % UInt64(i + 1))
            out.swapAt(i, j)
            i -= 1
        }
        return out
    }

    /// Flooring modulo: always in `0..<m`, including for negative `a`.
    ///
    /// Swift's `%` truncates toward zero, so `-1 % 3 == -1` — used directly as an array index
    /// that is a crash, and "fixed" with `abs` it is a silently MIRRORED walk. Written out
    /// because both wrong versions look right.
    static func floorMod(_ a: Int, _ m: Int) -> Int {
        guard m > 0 else { return 0 }
        let r = a % m                 // safe for Int.min: |r| < m, no overflow
        return r < 0 ? r + m : r
    }

    /// Flooring division, the companion of `floorMod`, so position and cycle stay consistent
    /// across zero: index −1 must be the LAST position of cycle −1, not position −1 of cycle 0.
    static func floorDiv(_ a: Int, _ m: Int) -> Int {
        guard m > 0 else { return 0 }
        let q = a / m
        return (a % m != 0 && a < 0) ? q - 1 : q
    }

    /// Addition that pins at `Int.max`/`Int.min` instead of trapping.
    ///
    /// Not defensive decoration: `surfacePoint` adds a decoded `octaveOffset` to a carry derived
    /// from a decoded `degreeIndex`, and Swift's `+` TRAPS on overflow — a corrupt stored value
    /// would be a crash on the 60 Hz self-play path, which is the worst possible place for one.
    /// `&+` would be wrong here in the other direction: it wraps, so `Int.max + 1` becomes
    /// `Int.min` and a ludicrously HIGH octave would clamp to the LOWEST band. Saturating keeps
    /// the sign of the intent, which is what the band clamp then reads.
    static func saturatingSum(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        guard overflow else { return sum }
        return a > 0 ? Int.max : Int.min
    }
}
