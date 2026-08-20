// BioVariationMaze.swift
// Echoel — the "idea-maze" for bio-generative music (vision-gate 2026-07-14, ADOPT→PRODUCT).
//
// Inspiration (founder reel @jakebeau_ → Anthropic "Effective harnesses for long-running
// agents"): an agent proposes MANY variations, SCORES each, and keeps the best on a
// leaderboard. Echoel's on-vision reinterpretation — "the body curates the ideas":
//
//   Given the current bio snapshot, explore N deterministic VARIATIONS of the same
//   piece (same structural skeleton, different melodic/rhythmic detail), score each by
//   how closely its realized groove-density matches what the DRIVER is asking for
//   (BioComposer.musicalState → `busy`), and return a ranked leaderboard. The musician
//   auditions the top ideas and picks.
//
// PURE value math on the control plane. Foundation-only, deterministic (seeded — same
// bio + base seed ⇒ same leaderboard, across launches and peers), no Date/Random, no
// audio-thread work, no allocation on any render path. Reuses BioComposer.compose (pure)
// — it does NOT reimplement composition.
//
// ⛔ "Nothing wires it to the engine yet; it is a pure core like VBAPPanner / AmbisonicsEncode
// until a Touch 'audition the maze' surface … lands in later cycles" STOOD HERE AND THE SURFACE
// HAD LANDED. `variationsCard` is mounted in `tempoToolsPanel`, which the "Tempo & variations"
// chip opens; its "Explore" button calls `explore(base:count:)` and its rows apply a candidate.
// The staleness predates #645, but that slice added a doc block sixty lines below describing the
// card this header said did not exist — a file arguing with itself, which is the exact drift the
// #627 honesty family exists to remove. **A "not wired yet" note is a claim with an expiry date
// and no alarm**: the commit that wires it has no reason to look at the file header of the pure
// core it just consumed. The math below is still pure and still Foundation-only; that half was
// never wrong.
//
// The score is TRANSPARENT and honest (principle 3, biofeedback-is-science): it is the
// closeness of realized density to the DRIVER's requested busy-ness — a number the UI can
// show. It is NOT a health/benefit claim. ⛔ The sample copy that stood here — "this take
// matches your current calm 0.82" — was a USER-FACING string inside a developer comment, and
// it carried the exact possessive #645 had to remove from the shipped card. A sample string
// in a doc is a template the next surface copies; it gets the same bar as shipped copy.

import Foundation

/// Bio-curated variation search over BioComposer: propose → score → rank.
public enum BioVariationMaze {

    /// One explored variation and why it ranked where it did.
    public struct Candidate: Sendable, Equatable {
        /// The melodic-detail seed that produced this variation (the skeleton is shared).
        public let seed: UInt64
        /// Realized groove density 0…1 (how busy the take actually is).
        public let realizedDensity: Double
        /// Bio-fit score 0…1, higher = closer to what the driver is asking for.
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
        /// The density the DRIVER is currently asking for (0…1) — the target every
        /// candidate is scored against. Surfaced so the UI can show the "why".
        ///
        /// ⛔ "the body" STOOD HERE and it is the line a session reads before writing the next
        /// sentence about this value (#645 review). It is computed from the composer input,
        /// which comes from `bus.usableBio()` — under the Simulation source that is the demo
        /// generator's fabricated frame, and with no source at all it is the engine's own
        /// neutral default. `BioVariationMaze.boardSentence(driver:density:)` is where the
        /// three honest phrasings live; do not re-derive a possessive one from this doc.
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

    /// The card's one-line explanation of a board, with its driver named (#645).
    ///
    /// ⛔ THE SHIPPED STRING ATTRIBUTED A PREFERENCE TO THE READER THAT NOBODY EXPRESSED. It read
    /// "Ideas from your pulse — tap to keep. Your body wants a full groove." unconditionally, and
    /// `targetDensity` traces `BioComposer.musicalState` → the composer input → `bus.usableBio()`
    /// — which under the Simulation source is the demo generator's fabricated frame, and with no
    /// source at all is the engine's own default. Of everything the #627 honesty family has had
    /// to correct this is the strongest claim: not "your body is at 62%" but "your body WANTS
    /// this", a desire put in the reader's mouth.
    ///
    /// ⭐ `.body` KEEPS "wants" UNCHANGED. The anthropomorphism is the founder's shipped voice and
    /// it is TRUE when a real body was read; rewriting it would be the over-correction this family
    /// has already had to retract twice. Only the SUBJECT moves.
    ///
    /// ⚠️ `.nothingMeasured` IS NOT A COSMETIC THIRD CASE — it is the one #644's `Bool` could not
    /// express, one slice ago, on the surface next door. With no frame the target is the engine's
    /// default, so naming any body at all invents the reason the ideas are ranked the way they
    /// are.
    public static func boardSentence(driver: BioNarrationDriver, density: String) -> String {
        switch driver {
        case .body:
            return "Ideas from your pulse — tap to keep. Your body wants \(density)."
        case .simulatedDemo:
            return "Ideas from " + BioProvenanceCopy.demoSubject + " — tap to keep. "
                + "The demo asks for \(density)."
        case .nothingMeasured:
            return "No pulse was measured, so these are ranked against the engine's own "
                + "target — tap to keep. They aim for \(density)."
        }
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

    /// Bio-fit score 0…1: how close a realized density sits to the target the driver asks
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
        // What the driver is asking for, from the SAME model BioComposer uses. "driver",
        // not "body": under Simulation this input came from the demo generator (#645).
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
