// LaneComposerInput.swift
// Per-track composition (Module 2 of the per-instrument restructure): apply ONE
// lane's optional composition overrides — genre / mood / variation — onto the
// global BioComposer.Input, so that lane composes in its OWN character while every
// unset field keeps following the global body-driven take. Founder 2026-07-14:
// "Genre und Variation pro MIDI-Spur einzeln … Mood kommt zu Genre und Variationen."
//
// PURE seam (Foundation-only, deterministic) — the per-lane generate fan-out that
// places each lane's clip calls this; unit-tested on Linux without any audio/engine.
// The shared skeleton (structureSeed) is deliberately LEFT ALONE so lanes in the
// SAME genre stay cohesive (same journey, different variation); a different genre
// already draws its own progression/register, so it diverges on its own.

import Foundation

/// Applies a `TimelineLane`'s per-track composition overrides to a base composer input.
public enum LaneComposerInput {

    /// The base input with this lane's overrides applied:
    /// - `genreOverride` → `style` (this lane composes in its own genre)
    /// - `mood`          → `mood`  (this lane's own character)
    /// - `variationSeed` → `seed`  (this lane's own melodic variation; the DETAIL seed,
    ///                              so the shared structureSeed keeps same-genre lanes cohesive)
    /// Every `nil` field passes the global value through unchanged — a lane with no
    /// overrides yields a byte-identical input (the primary/global take).
    ///
    /// CALLER CONTRACT: pass a `base` whose `structureSeed` is NON-NIL for the
    /// same-genre cohesion above to hold. When `base.structureSeed == nil`,
    /// BioComposer derives the skeleton from `seed`, so a `variationSeed`-only lane
    /// would shift BOTH detail and skeleton (no shared skeleton to protect). The
    /// generate fan-out already computes a body-stable `structureSeed` — reuse it.
    public static func apply(_ lane: TimelineLane, to base: BioComposer.Input) -> BioComposer.Input {
        var input = base
        if let genre = lane.genreOverride { input.style = genre }
        if let mood = lane.mood { input.mood = mood }
        if let variationSeed = lane.variationSeed { input.seed = variationSeed }
        return input
    }

    /// True when this lane carries ANY per-track composition override — the caller
    /// can skip the per-lane compose entirely (reuse the global take) when false.
    public static func hasOverride(_ lane: TimelineLane) -> Bool {
        lane.genreOverride != nil || lane.mood != nil || lane.variationSeed != nil
    }
}
