// BioVariationMaze.swift
// Echoel — the "idea-maze" for bio-generative music (vision-gate 2026-07-14, ADOPT→PRODUCT).
//
// Inspiration (founder reel @jakebeau_ → Anthropic "Effective harnesses for long-running
// agents"): an agent proposes MANY variations, SCORES each, and keeps the best on a
// leaderboard. Echoel's on-vision reinterpretation — "the body curates the ideas":
//
//   Given the current bio snapshot, explore N deterministic VARIATIONS of the same
//   piece (same structural skeleton, different melodic/rhythmic detail), score each by
//   how closely its realized groove-density matches what the body is asking for
//   (BioComposer.musicalState → `busy`), and return a ranked leaderboard. The musician
//   auditions the top ideas and picks.
//
// PURE value math on the control plane. Foundation-only, deterministic (seeded — same
// bio + base seed ⇒ same leaderboard, across launches and peers), no Date/Random, no
// audio-thread work, no allocation on any render path. Reuses BioComposer.compose (pure)
// — it does NOT reimplement composition. Nothing wires it to the engine yet; it is a
// pure core like VBAPPanner / AmbisonicsEncode until a Touch "audition the maze" surface
// and/or the EchoelAI brain (LLM-assisted proposals) land in later cycles.
//
// The score is TRANSPARENT and honest (principle 3, biofeedback-is-science): it is the
// closeness of realized density to the body's requested busy-ness — a number the UI can
// show ("this take matches your current calm 0.82"). It is NOT a health/benefit claim.

import Foundation

/// Bio-curated variation search over BioComposer: propose → score → rank.
public enum BioVariationMaze {

    /// One explored variation and why it ranked where it did.
    public struct Candidate: Sendable, Equatable {
        /// The melodic-detail seed that produced this variation (the skeleton is shared).
        public let seed: UInt64
        /// Realized groove density 0…1 (how busy the take actually is).
        public let realizedDensity: Double
        /// Bio-fit score 0…1, higher = closer to what the body is asking for.
        public let score: Double
        /// The composed take (pure BioComposer output).
        public let composition: BioComposition

        public init(seed: UInt64, realizedDensity: Double, score: Double,
                    composition: BioComposition) {
            self.seed = seed
            self.realizedDensity = realizedDensity
            self.score = score
            self.composition = composition
        }
    }

    /// A ranked exploration, plus the transparent target it was scored against.
    public struct Leaderboard: Sendable, Equatable {
        /// The density the body is currently asking for (0…1) — the target every
        /// candidate is scored against. Surfaced so the UI can show the "why".
        public let targetDensity: Double
        /// Candidates, best-first (highest score). Deterministic order.
        public let candidates: [Candidate]

        public init(targetDensity: Double, candidates: [Candidate]) {
            self.targetDensity = targetDensity
            self.candidates = candidates
        }

        /// The winning idea, if any.
        public var best: Candidate? { candidates.first }
    }

    // MARK: - Seed enumeration

    /// A deterministic, well-distributed variation seed from a base seed + index
    /// (splitmix64 finalizer). No RNG state to leak; the same (base, index) always
    /// yields the same seed, so the whole maze is reproducible.
    public static func variantSeed(base: UInt64, index: Int) -> UInt64 {
        var z = base &+ (UInt64(bitPattern: Int64(index)) &+ 1) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    // MARK: - Scoring

    /// Realized groove density of a composition, 0…1. Drum-hit fraction is the primary
    /// signal; note count is a secondary term so purely-melodic styles (no drums) still
    /// discriminate between variations. A documented heuristic, not a claim.
    public static func realizedDensity(_ comp: BioComposition) -> Double {
        let cells = comp.drumSteps.reduce(0) { $0 + $1.count }
        let hits  = comp.drumSteps.reduce(0) { $0 + $1.filter { $0 }.count }
        let drumDensity = cells > 0 ? Double(hits) / Double(cells) : 0
        // 16 sounding notes across the loop reads as "full" for the melodic term.
        let noteDensity = min(1.0, Double(comp.notes.count) / 16.0)
        let raw = cells > 0 ? (0.7 * drumDensity + 0.3 * noteDensity) : noteDensity
        return min(1, max(0, raw))
    }

    /// Bio-fit score 0…1: how close a realized density sits to the target the body asks
    /// for. 1 = exact match, falling linearly with the gap.
    public static func score(realizedDensity: Double, targetDensity: Double) -> Double {
        let gap = abs(realizedDensity - targetDensity)
        return min(1, max(0, 1 - gap))
    }

    // MARK: - Explore

    /// Explore `count` variations of the same piece and rank them by bio-fit.
    ///
    /// All variations share ONE structural skeleton (so they are variations of the SAME
    /// piece, not random new pieces — cohesion, per BioComposer.structureSeed): the
    /// skeleton is `base.structureSeed ?? base.seed`, and only the melodic-detail `seed`
    /// varies. The first candidate is always the base take itself, so the leaderboard
    /// always shows "what you have now" alongside the alternatives.
    ///
    /// - Parameters:
    ///   - base: the current bio-driven composer input (the take you have now).
    ///   - count: how many variations to explore (clamped to ≥ 1).
    /// - Returns: a `Leaderboard`, best-first, with the transparent target density.
    public static func explore(base: BioComposer.Input, count: Int) -> Leaderboard {
        let n = max(1, count)
        // What the body is asking for, from the SAME model BioComposer uses.
        let state = BioComposer.musicalState(coherence: base.coherence,
                                             hrvNormalized: base.hrvNormalized,
                                             heartRateBPM: Double(base.heartRateBPM))
        let target = Double(state.busy)

        // Pin the shared skeleton so every variation is the same piece evolving.
        let skeleton = base.structureSeed ?? base.seed

        // Candidate 0 = the base take; 1..<n = deterministic variations.
        var seeds: [UInt64] = [base.seed]
        for i in 1..<n { seeds.append(variantSeed(base: base.seed, index: i)) }

        let candidates: [Candidate] = seeds.map { seed in
            var input = base
            input.seed = seed
            input.structureSeed = skeleton
            let comp = BioComposer.compose(input)
            let density = realizedDensity(comp)
            return Candidate(seed: seed,
                             realizedDensity: density,
                             score: score(realizedDensity: density, targetDensity: target),
                             composition: comp)
        }

        // Rank best-first. Deterministic tie-break on seed so the order never wobbles.
        let ranked = candidates.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.seed < $1.seed
        }
        return Leaderboard(targetDensity: target, candidates: ranked)
    }
}
