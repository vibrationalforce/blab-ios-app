// VoiceLeader.swift
// Echoel — H1 (Harmony-Core, scratchpads/PLAN_HARMONY_CORE.md): the PURE
// voice-leading resolver. Given the previously sounding voicing and the target
// chord's pitch classes, it picks the inversion/register of the target chord
// with minimal total voice movement — common tones held, the rest moving
// stepwise, like a player — instead of the parallel block jump.
//
// PURE seam (Foundation-only, deterministic — no Date, no SystemRandom, no
// state): compose-time on the main actor, never the audio thread. BioComposer
// wires it for the Harmony-role chords in the NEXT slice via an opt-in
// composer-input switch; until then nothing calls it, so the app stays
// bit-identical (Golden law of the plan).
//
// Laws (tested in VoiceLeaderTests):
//   • Candidates are real chord voicings: `previousVoicing.count` distinct
//     in-register pitches whose pitch classes come from the target chord —
//     every chord tone covered when the voice count allows it, never a unison,
//     and no octave doubling unless there are more voices than pitch classes.
//   • Cost = Σ|Δ| over SORTED pairwise voice assignment (ascending previous
//     voice i moves to ascending candidate voice i — the monotone, non-crossing
//     matching, which minimizes the L1 sum for sorted sequences), MINUS a
//     rebate per held common tone, PLUS a spread term (close ↔ open ambitus).
//   • strictness 1 = the strict cost optimum; toward 0 a deterministic,
//     seed-selected pick from the best few candidates (freer, never random).
//   • spread 0 prefers close position, 1 open position, 0.5 is neutral.
//   • Empty previous voicing ⇒ a compact voicing centred in the register.
//   • Every returned pitch lies inside `register`; NaN controls read neutral.

import Foundation

public enum VoiceLeader {

    // MARK: Cost-model weights (the tested laws — change only with the tests)

    /// Rebate per held common tone (exact pitch kept across the change). Worth
    /// more than a semitone of movement, less than a restructure: holding a tone
    /// beats an equal-|Δ| alternative without ever outweighing real distance.
    static let commonToneRebate: Float = 1.5

    /// Weight of the close↔open ambitus preference. Deliberately soft (a few
    /// semitones of "shape wish") so it colours the choice without overriding
    /// minimal movement or common tones.
    static let spreadWeight: Float = 0.35

    /// Weight pulling a from-nothing voicing toward the register centre
    /// (only active when `previousVoicing` is empty — otherwise movement
    /// anchors the register).
    static let centerWeight: Float = 0.3

    /// Upper bound on enumerated candidates — a safety valve for pathological
    /// inputs (huge register × many voices). Enumeration order is fixed, so a
    /// capped run is still deterministic.
    static let candidateCap = 20_000

    /// Loose strictness picks from at most this many of the cheapest candidates.
    static let looseWindow = 8

    // MARK: Resolve

    /// Voice the target chord so it connects to `previousVoicing` with minimal
    /// total voice movement.
    ///
    /// - Parameters:
    ///   - previousVoicing: the sounding MIDI pitches (any order). Its COUNT
    ///     fixes the result's voice count. Empty ⇒ a compact voicing around the
    ///     register centre with one voice per distinct chord pitch class.
    ///   - chordPitches: the target chord as pitch classes 0…11 OR full MIDI
    ///     pitches (reduced mod 12) — matching BioComposer's real material,
    ///     where chords are `[Int]` from `MusicalKey.degree`. Empty ⇒ nothing
    ///     to voice: the previous voicing is returned register-clamped.
    ///   - register: allowed MIDI range for every returned pitch.
    ///   - strictness: 0…1. 1 = the strict cost optimum; toward 0 the pick
    ///     relaxes to a deterministic, `seed`-selected choice among the best
    ///     few candidates. Non-finite reads as 1.
    ///   - spread: 0…1 close↔open voicing preference; 0.5 neutral. Non-finite
    ///     reads as 0.5.
    ///   - seed: selects the alternative when `strictness < 1` (SeededRNG —
    ///     reproducible, never SystemRandom).
    /// - Returns: the chosen voicing, ascending. Callers map voices as needed.
    public static func resolve(from previousVoicing: [Int],
                               to chordPitches: [Int],
                               register: ClosedRange<Int>,
                               strictness: Float,
                               spread: Float,
                               seed: UInt64 = 0) -> [Int] {
        guard !distinctPitchClasses(chordPitches).isEmpty else {
            // No chord ⇒ nothing to lead; hold what sounds, inside the register.
            return previousVoicing.map { Swift.min(Swift.max($0, register.lowerBound), register.upperBound) }
        }
        let ranked = rankedCandidates(from: previousVoicing, to: chordPitches,
                                      register: register, spread: spread)
        guard !ranked.isEmpty else { return [] }   // unreachable: fallback guarantees ≥ 1
        let strict = sanitizedUnit(strictness, fallback: 1)
        let window = 1 + Int((Float(Swift.min(ranked.count, looseWindow) - 1) * (1 - strict)).rounded())
        guard window > 1 else { return ranked[0].voicing }
        var rng = SeededRNG(seed: seed)
        return ranked[Int(rng.next() % UInt64(window))].voicing
    }

    // MARK: Ranking (exposed: the optimality tests pin it, H2 ChordSuggest ranks with it)

    /// Every admissible voicing of the target chord with its total cost, sorted
    /// ascending by (cost, then lexicographic voicing — the deterministic
    /// tie-break). `resolve` selects from this list; H2's chord ranking reads
    /// the head cost as its voice-leading distance term.
    public static func rankedCandidates(from previousVoicing: [Int],
                                        to chordPitches: [Int],
                                        register: ClosedRange<Int>,
                                        spread: Float) -> [(voicing: [Int], cost: Float)] {
        let pcs = distinctPitchClasses(chordPitches)
        guard !pcs.isEmpty else { return [] }
        let prev = previousVoicing.sorted()
        let voiceCount = prev.isEmpty ? pcs.count : prev.count
        var candidates = candidateVoicings(voiceCount: voiceCount, pitchClasses: pcs,
                                           previous: prev, register: register)
        if candidates.isEmpty {
            // Register too narrow for a real enumeration — the guard path still
            // returns something playable and in range.
            candidates = [fallbackStack(voiceCount: voiceCount, pitchClasses: pcs,
                                        register: register)]
        }
        let sp = sanitizedUnit(spread, fallback: 0.5)
        let ambits = candidates.map { Float(($0.last ?? 0) - ($0.first ?? 0)) }
        let minAmbitus = ambits.min() ?? 0
        let maxAmbitus = ambits.max() ?? 0
        let center = Float(register.lowerBound + register.upperBound) / 2
        var ranked: [(voicing: [Int], cost: Float)] = []
        ranked.reserveCapacity(candidates.count)
        for (i, cand) in candidates.enumerated() {
            var cost: Float
            if prev.isEmpty {
                // From nothing: no movement to minimize — sit around the centre.
                guard !cand.isEmpty else { continue }
                let mean = Float(cand.reduce(0, +)) / Float(cand.count)
                cost = centerWeight * abs(mean - center)
            } else {
                cost = movementCost(from: prev, to: cand)
            }
            // Close↔open: linear pull toward the narrowest (spread 0) or widest
            // (spread 1) available ambitus; exactly neutral at 0.5.
            cost += spreadWeight * ((1 - sp) * (ambits[i] - minAmbitus)
                                    + sp * (maxAmbitus - ambits[i]))
            ranked.append((voicing: cand, cost: cost))
        }
        ranked.sort {
            $0.cost != $1.cost ? $0.cost < $1.cost
                               : $0.voicing.lexicographicallyPrecedes($1.voicing)
        }
        return ranked
    }

    /// Movement cost between two voicings: Σ|Δ| over the sorted pairwise voice
    /// assignment (ascending i-th → ascending i-th; the non-crossing matching
    /// minimizes the L1 sum for sorted sequences) minus `commonToneRebate` per
    /// exactly-held pitch (multiset intersection). Voice-count mismatch pairs
    /// the overlapping prefix and ignores the surplus voices.
    public static func movementCost(from previous: [Int], to candidate: [Int]) -> Float {
        let a = previous.sorted()
        let b = candidate.sorted()
        var moved: Float = 0
        for i in 0..<Swift.min(a.count, b.count) {
            moved += Float(abs(a[i] - b[i]))
        }
        var common = 0
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { common += 1; i += 1; j += 1 }
            else if a[i] < b[j] { i += 1 }
            else { j += 1 }
        }
        return moved - commonToneRebate * Float(common)
    }

    // MARK: Candidate enumeration

    /// All ascending combinations of `voiceCount` DISTINCT in-register pitches
    /// drawn from the chord's pitch classes, subject to:
    ///   • voiceCount ≥ pitch-class count ⇒ every chord tone covered (extra
    ///     voices double a tone at another octave — the only allowed doubling);
    ///   • voiceCount <  pitch-class count ⇒ no doubled pitch class at all.
    /// A locality window around the previous voicing (or the register centre)
    /// bounds the combinatorics; enumeration order is fixed ⇒ deterministic.
    static func candidateVoicings(voiceCount: Int, pitchClasses: [Int],
                                  previous: [Int],
                                  register: ClosedRange<Int>) -> [[Int]] {
        guard voiceCount > 0, !pitchClasses.isEmpty else { return [] }
        let pcSet = Set(pitchClasses)
        let fullPool = register.filter { pcSet.contains(pitchClass($0)) }   // ascending

        // Locality window: voices rarely leap past a 10th, and a from-nothing
        // voicing lives near the centre — thinning the pool keeps the
        // enumeration small without touching any realistic candidate.
        let windowed: [Int]
        if let lo = previous.first, let hi = previous.last {
            windowed = fullPool.filter { $0 >= lo - 18 && $0 <= hi + 18 }
        } else {
            let center = (register.lowerBound + register.upperBound) / 2
            windowed = fullPool.filter { $0 >= center - 30 && $0 <= center + 30 }
        }
        let needCoverage = voiceCount >= pcSet.count
        func viable(_ pool: [Int]) -> Bool {
            pool.count >= voiceCount
                && (!needCoverage || Set(pool.map(pitchClass)).isSuperset(of: pcSet))
        }
        let pool = viable(windowed) ? windowed : fullPool
        guard viable(pool) else { return [] }

        var result: [[Int]] = []
        var combo: [Int] = []
        func recurse(_ start: Int, _ covered: Set<Int>) {
            guard result.count < candidateCap else { return }
            if combo.count == voiceCount {
                if !needCoverage || covered.isSuperset(of: pcSet) { result.append(combo) }
                return
            }
            let slotsLeft = voiceCount - combo.count
            guard pool.count - start >= slotsLeft else { return }
            if needCoverage {
                // Prune: the remaining slots must be able to cover the missing tones.
                guard pcSet.subtracting(covered).count <= slotsLeft else { return }
            }
            for idx in start..<pool.count {
                let pc = pitchClass(pool[idx])
                if !needCoverage && covered.contains(pc) { continue }   // no doubling
                combo.append(pool[idx])
                recurse(idx + 1, covered.union([pc]))
                combo.removeLast()
                guard result.count < candidateCap else { return }
            }
        }
        recurse(0, [])
        return result
    }

    /// Guard path for a register too narrow to enumerate real voicings: stack
    /// the chord tones upward from the pitch nearest the register centre,
    /// clamping at the top. Always returns `voiceCount` in-register pitches.
    static func fallbackStack(voiceCount: Int, pitchClasses: [Int],
                              register: ClosedRange<Int>) -> [Int] {
        guard voiceCount > 0, let firstPC = pitchClasses.first else { return [] }
        let center = (register.lowerBound + register.upperBound) / 2
        var out = [nearestPitch(pitchClass: firstPC, to: center, in: register)]
        for i in 1..<voiceCount {
            let pc = pitchClasses[i % pitchClasses.count]
            var p = (out[out.count - 1]) + 1
            while p <= register.upperBound && pitchClass(p) != pc { p += 1 }
            out.append(Swift.min(p, register.upperBound))
        }
        return out
    }

    // MARK: Small pure helpers

    /// Normalized pitch class 0…11 of any (possibly negative) pitch.
    static func pitchClass(_ pitch: Int) -> Int { ((pitch % 12) + 12) % 12 }

    /// Distinct pitch classes in first-occurrence order.
    static func distinctPitchClasses(_ pitches: [Int]) -> [Int] {
        var seen = Set<Int>()
        var out: [Int] = []
        for p in pitches {
            let pc = pitchClass(p)
            if seen.insert(pc).inserted { out.append(pc) }
        }
        return out
    }

    /// The in-register pitch of the given class nearest `target` (tie → lower);
    /// register-clamped when the class does not occur inside the register.
    static func nearestPitch(pitchClass pc: Int, to target: Int,
                             in register: ClosedRange<Int>) -> Int {
        var best: Int?
        var bestDist = Int.max
        var p = register.lowerBound
        while p <= register.upperBound {
            if pitchClass(p) == pitchClass(pc) {
                let d = abs(p - target)
                if d < bestDist { best = p; bestDist = d }   // < keeps the lower on ties
            }
            p += 1
        }
        return best ?? Swift.min(Swift.max(target, register.lowerBound), register.upperBound)
    }

    /// Clamp a control into 0…1; non-finite values read as `fallback` (repo NaN
    /// precedent: fail neutral, never full-scale).
    static func sanitizedUnit(_ x: Float, fallback: Float) -> Float {
        guard x.isFinite else { return fallback }
        return Swift.min(Swift.max(x, 0), 1)
    }
}
