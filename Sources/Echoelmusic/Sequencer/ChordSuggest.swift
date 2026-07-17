// ChordSuggest.swift
// Echoel — H2 (Harmony-Core, scratchpads/PLAN_HARMONY_CORE.md): the PURE
// function-aware chord suggester. Given the current key, the previous chord and
// its sounding voicing, it ranks every candidate next chord — the diatonic
// third-stack triads of the key plus a SHORT curated modal-interchange list —
// by classical harmonic-function logic (tonic → subdominant → dominant
// tendency, cadence resolution D → T) with the VoiceLeader head cost as the
// smoothness term, and a coherence selector then picks from that ranking: a
// settled body gets the expected consonant continuation (the top pick), an
// unsettled one reaches deeper into the list for tension. Seed-stable
// (SeededRNG on its OWN salted stream — no draws consumed from any compose
// stream), Foundation-only, deterministic, compose-time — never the audio
// thread. BioComposer wires it via the opt-in `Input.suggestJourney` switch;
// off (default) is byte-identical to the legacy progression logic.
//
// THEORY (own derivation — standard harmony-textbook material only):
//   • Diatonic candidates: a triad stacked in thirds (degrees d, d+2, d+4) on
//     every scale degree, classified T/S/D by the ROOT's semitone interval from
//     the tonic: {0,3,4,8,9} tonic family (I/iii/vi colours), {1,2,5,6}
//     subdominant family (ii/IV colours), {7,10,11} dominant family
//     (V/vii colours). Total for any scale length, so exotic scales rank too.
//   • Curated borrowings (modal interchange, one short list per tonality):
//       major tonality → iv (minor subdominant), bVI major, bVII major
//         (all borrowed from the parallel minor; bVII acts as the back-door
//         dominant);
//       minor tonality → V major (the raised leading tone), I major (the
//         Picardy tonic), bII major (the Neapolitan).
//     Each borrowing is derived, not hard-coded per key: the nearest diatonic
//     third-stack (every tone within a semitone) plus per-tone alterations,
//     minimal total alteration wins, and a borrowing that is ALREADY diatonic
//     in the current scale is skipped (no duplicate candidate). The composer
//     renders a candidate through `MusicalKey.degree` + `alteration(...)`, so
//     pad, bass and lead all agree on the same spelling.
//
// Laws (tested in ChordSuggestTests):
//   • Cadence: after a dominant-function chord the top-ranked candidate is
//     tonic-function. In general the zero-cost function target outranks every
//     other class: the distance term is capped at
//     `distanceWeight · distanceCap` = 1.2, strictly below the smallest
//     function step (0.35 · `functionWeight` = 1.4).
//   • VoiceLeader distance breaks ties inside a function class.
//   • Borrowed chords never rank top-1 (`borrowedSurcharge` 3 > 1.2) — they are
//     the TENSION reservoir the low-coherence selector reaches into.
//   • Selection: coherence 1 → window 1 (always the top pick); coherence 0 →
//     window `maxSelectionWindow`; monotone in between; non-finite coherence
//     reads as 1 (fail neutral/consonant). Deterministic per seed.

import Foundation

public enum ChordSuggest {

    // MARK: Types

    /// Classical harmonic function family of a chord root.
    public enum HarmonicFunction: String, Sendable, Equatable {
        case tonic, subdominant, dominant
    }

    /// One suggested chord: a diatonic third-stack root plus per-tone semitone
    /// alterations (all zero = purely diatonic; a borrowing alters 1–2 tones).
    /// `alterations` aligns with the stacked tones [root, third, fifth]
    /// (degree offsets 0/2/4) — `alteration(forToneOffset:...)` maps any
    /// composer tone offset onto it.
    public struct Candidate: Equatable, Sendable {
        public var rootDegree: Int
        public var alterations: [Int]
        public var function: HarmonicFunction
        public var borrowed: Bool

        public init(rootDegree: Int, alterations: [Int],
                    function: HarmonicFunction, borrowed: Bool) {
            self.rootDegree = rootDegree
            self.alterations = alterations
            self.function = function
            self.borrowed = borrowed
        }
    }

    // MARK: Cost-model weights (the tested laws — change only with the tests)

    /// Scale of the harmonic-function step costs. The smallest non-zero step
    /// (0.35) times this must stay ABOVE the distance term's ceiling so
    /// function logic always outranks smoothness (which then breaks ties).
    static let functionWeight: Float = 4

    /// Flat surcharge on modal-interchange candidates: above the in-class
    /// ceiling (1.2) so a borrowing never ranks top-1, below the far function
    /// steps so the tension window still reaches it.
    static let borrowedSurcharge: Float = 3

    /// Penalty for suggesting the immediately previous chord again.
    static let repeatPenalty: Float = 2

    /// Weight of the VoiceLeader head cost (the smoothness tie-break).
    static let distanceWeight: Float = 0.15

    /// Clamp on the head cost before weighting — caps the distance term at
    /// 0.15 · 8 = 1.2, strictly under the smallest function step (1.4).
    static let distanceCap: Float = 8

    /// At coherence 0 the selector picks among this many of the top candidates.
    static let maxSelectionWindow = 6

    /// Seed salt for the H2 stream ("CHRDSGST" in ASCII): XOR-derived from the
    /// caller's skeleton seed WITHOUT consuming any other RNG stream (H1/H3
    /// wiring discipline), decorrelated from the H3 humanize salt.
    static let seedSalt: UInt64 = 0x4348_5244_5347_5354

    // MARK: Candidates

    /// Every candidate next chord in the key: one diatonic third-stack per
    /// scale degree, then the curated borrowings for the key's tonality.
    public static func candidates(in key: MusicalKey) -> [Candidate] {
        let n = key.degreesPerOctave
        guard n > 0 else { return [] }
        var out: [Candidate] = []
        out.reserveCapacity(n + 3)
        for d in 0..<n {
            let interval = ((pitchClass(key.degree(d, octave: 0)) - key.root) % 12 + 12) % 12
            out.append(Candidate(rootDegree: d, alterations: [0, 0, 0],
                                 function: diatonicFunction(interval: interval),
                                 borrowed: false))
        }
        out.append(contentsOf: borrowedCandidates(in: key))
        return out
    }

    /// T/S/D family of a chord root by its semitone interval from the tonic.
    static func diatonicFunction(interval: Int) -> HarmonicFunction {
        switch ((interval % 12) + 12) % 12 {
        case 0, 3, 4, 8, 9: return .tonic        // I / iii / vi colours
        case 1, 2, 5, 6:    return .subdominant  // ii / IV colours
        default:            return .dominant     // 7, 10, 11 — V / vii colours
        }
    }

    /// The curated modal-interchange list for the key's tonality, derived per
    /// key (see the header). Targets are semitone intervals from the tonic.
    static func borrowedCandidates(in key: MusicalKey) -> [Candidate] {
        let curated: [(intervals: [Int], function: HarmonicFunction)]
        if key.scale.isMinorTonality {
            curated = [([7, 11, 2], .dominant),    // V major — raised leading tone
                       ([0, 4, 7], .tonic),        // I major — Picardy tonic
                       ([1, 5, 8], .subdominant)]  // bII major — Neapolitan
        } else {
            curated = [([5, 8, 0], .subdominant),  // iv — minor subdominant
                       ([8, 0, 3], .subdominant),  // bVI major
                       ([10, 2, 5], .dominant)]    // bVII major — back-door dominant
        }
        return curated.compactMap {
            borrowedCandidate(targetIntervals: $0.intervals, function: $0.function, in: key)
        }
    }

    /// Express a target chord (semitone intervals from the tonic, root first)
    /// as the nearest diatonic third-stack plus per-tone alterations: every
    /// tone must sit within ±1 semitone of the stack; minimal total alteration
    /// wins (tie → lower degree). Returns nil when no stack fits or when the
    /// chord is already diatonic (total 0 — it exists as a plain candidate).
    static func borrowedCandidate(targetIntervals: [Int], function: HarmonicFunction,
                                  in key: MusicalKey) -> Candidate? {
        let n = key.degreesPerOctave
        guard n > 0, targetIntervals.count == 3 else { return nil }
        let targetPCs = targetIntervals.map { ((key.root + $0) % 12 + 12) % 12 }
        var best: (degree: Int, alts: [Int], total: Int)?
        for d in 0..<n {
            var alts: [Int] = []
            var total = 0
            var fits = true
            for (i, tone) in [0, 2, 4].enumerated() {
                let pc = pitchClass(key.degree(d + tone, octave: 0))
                var diff = (targetPCs[i] - pc) % 12
                if diff > 6 { diff -= 12 }
                if diff < -6 { diff += 12 }
                guard abs(diff) <= 1 else { fits = false; break }
                alts.append(diff)
                total += abs(diff)
            }
            guard fits else { continue }
            if let current = best {
                if total < current.total { best = (d, alts, total) }
            } else {
                best = (d, alts, total)
            }
        }
        guard let found = best, found.total > 0 else { return nil }
        return Candidate(rootDegree: found.degree, alterations: found.alts,
                         function: function, borrowed: true)
    }

    // MARK: Pitch material

    /// The candidate's sounding pitch classes (root, third, fifth) in the key.
    public static func pitchClasses(of candidate: Candidate, in key: MusicalKey) -> [Int] {
        [0, 2, 4].enumerated().map { i, tone in
            let alt = i < candidate.alterations.count ? candidate.alterations[i] : 0
            return pitchClass(key.degree(candidate.rootDegree + tone, octave: 0) + alt)
        }
    }

    /// Map a composer tone offset (scale-degree offset above the chord root,
    /// e.g. 0/2/4 triad, 6 = 7th, 7 = octave in a 7-note scale) onto the
    /// candidate's alteration for that stack member. Tones outside the altered
    /// [root, third, fifth] stack (odd offsets, the 7th) read 0 — a borrowing
    /// alters only its own triad tones; everything else stays diatonic.
    static func alteration(forToneOffset tone: Int, degreesPerOctave n: Int,
                           in alterations: [Int]) -> Int {
        guard !alterations.isEmpty, n > 0 else { return 0 }
        let t = ((tone % n) + n) % n   // octave-wrapped stack position
        guard t % 2 == 0, t / 2 < alterations.count else { return 0 }
        return alterations[t / 2]
    }

    // MARK: Ranking

    /// Cost of moving from one harmonic function to the next — the classical
    /// T → S → D → T circulation: continuing the cycle is free, the cadence
    /// D → T is free, retrogressions and standing still cost more. `nil`
    /// previous = the take's first chord (the tonic opens).
    static func functionCost(from previous: HarmonicFunction?,
                             to next: HarmonicFunction) -> Float {
        guard let previous else {
            switch next {
            case .tonic:       return 0
            case .subdominant: return 0.35
            case .dominant:    return 0.5
            }
        }
        switch (previous, next) {
        case (.tonic, .subdominant):       return 0
        case (.tonic, .dominant):          return 0.35
        case (.tonic, .tonic):             return 0.7
        case (.subdominant, .dominant):    return 0
        case (.subdominant, .tonic):       return 0.5    // plagal fallback
        case (.subdominant, .subdominant): return 0.8
        case (.dominant, .tonic):          return 0      // the cadence resolution
        case (.dominant, .dominant):       return 0.6    // dominant prolongation
        case (.dominant, .subdominant):    return 1.0    // retrogression
        }
    }

    /// Rank the candidates for the NEXT chord. Score (lower = better) =
    /// function-tendency cost · `functionWeight` + `borrowedSurcharge` (if
    /// borrowed) + `repeatPenalty` (if it repeats `previous`) +
    /// `distanceWeight` · clamped VoiceLeader head cost from `previousVoicing`.
    /// Deterministic tie-break: diatonic before borrowed, then lower root
    /// degree, then lexicographic alterations.
    public static func rank(_ candidates: [Candidate], in key: MusicalKey,
                            after previous: Candidate?, previousVoicing: [Int],
                            register: ClosedRange<Int>)
        -> [(candidate: Candidate, score: Float)] {
        var scored: [(candidate: Candidate, score: Float)] = []
        scored.reserveCapacity(candidates.count)
        for cand in candidates {
            var score = functionWeight * functionCost(from: previous?.function,
                                                      to: cand.function)
            if cand.borrowed { score += borrowedSurcharge }
            if let prev = previous, prev.rootDegree == cand.rootDegree,
               prev.alterations == cand.alterations {
                score += repeatPenalty
            }
            let head = VoiceLeader.rankedCandidates(from: previousVoicing,
                                                    to: pitchClasses(of: cand, in: key),
                                                    register: register,
                                                    spread: 0.5).first?.cost ?? 0
            score += distanceWeight * Swift.min(Swift.max(head, 0), distanceCap)
            scored.append((candidate: cand, score: score))
        }
        scored.sort { a, b in
            if a.score != b.score { return a.score < b.score }
            if a.candidate.borrowed != b.candidate.borrowed { return !a.candidate.borrowed }
            if a.candidate.rootDegree != b.candidate.rootDegree {
                return a.candidate.rootDegree < b.candidate.rootDegree
            }
            return a.candidate.alterations.lexicographicallyPrecedes(b.candidate.alterations)
        }
        return scored
    }

    // MARK: Coherence selection

    /// How deep into the ranking the selector may reach: 1 at full coherence
    /// (the expected consonant top pick), `maxSelectionWindow` at zero
    /// coherence (tension — borrowings and remoter candidates come into
    /// range), monotone in between. Non-finite coherence reads as 1 (repo NaN
    /// precedent: fail neutral — here, consonant).
    static func selectionWindow(coherence: Float, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let c: Float = coherence.isFinite ? Swift.min(Swift.max(coherence, 0), 1) : 1
        let cap = Swift.min(count, maxSelectionWindow)
        return Swift.max(1, 1 + Int((Float(cap - 1) * (1 - c)).rounded()))
    }

    /// Seeded pick inside the coherence window. Draws exactly ONE value per
    /// call (also when the window is 1) so the stream advances identically at
    /// every coherence — same seed, same walk, different depth.
    static func selectIndex(coherence: Float, count: Int, rng: inout SeededRNG) -> Int {
        let window = selectionWindow(coherence: coherence, count: count)
        let draw = rng.next()
        guard window > 0 else { return 0 }
        return Int(draw % UInt64(window))
    }

    // MARK: Journey

    /// A whole seeded chord journey: starting from nothing, repeatedly rank
    /// the candidates after the previous pick (tracking the head voicing for
    /// the smoothness term) and let the coherence selector choose. At full
    /// coherence this is the pure functional cycle T → S → D → T…; low
    /// coherence digs into borrowings and remoter candidates. Deterministic
    /// per (key, coherence, register, seed); own salted stream.
    public static func journey(length: Int, in key: MusicalKey, coherence: Float,
                               register: ClosedRange<Int>, seed: UInt64) -> [Candidate] {
        guard length > 0 else { return [] }
        let pool = candidates(in: key)
        guard !pool.isEmpty else { return [] }
        var rng = SeededRNG(seed: seed ^ seedSalt)
        var out: [Candidate] = []
        out.reserveCapacity(length)
        var previous: Candidate?
        var voicing: [Int] = []
        for _ in 0..<length {
            let ranked = rank(pool, in: key, after: previous,
                              previousVoicing: voicing, register: register)
            guard !ranked.isEmpty else { break }   // unreachable: pool is non-empty
            let idx = selectIndex(coherence: coherence, count: ranked.count, rng: &rng)
            let pick = ranked[idx].candidate
            out.append(pick)
            previous = pick
            voicing = VoiceLeader.rankedCandidates(from: voicing,
                                                   to: pitchClasses(of: pick, in: key),
                                                   register: register,
                                                   spread: 0.5).first?.voicing ?? voicing
        }
        return out
    }

    // MARK: Small pure helpers

    /// Normalized pitch class 0…11 of any (possibly negative) pitch.
    static func pitchClass(_ pitch: Int) -> Int { ((pitch % 12) + 12) % 12 }
}
