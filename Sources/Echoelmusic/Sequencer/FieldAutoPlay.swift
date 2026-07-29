//
//  FieldAutoPlay.swift
//  Echoelmusic — Sequencer
//
//  THE FIELD PLAYING ITSELF (founder 2026-07-29: "Es soll auch eine Möglichkeit geben wie
//  der Synth selbst spielt ohne das man Touch bedienen muss. Natürlich mit mehreren
//  Parametern").
//
//  THE ONE DESIGN DECISION, and everything else follows from it: this emits POSITIONS on the
//  play surface, not notes. A generated touch is a touch — it goes through `TouchPitchMap`
//  exactly like a finger, and from there through the same key-quantisation, the same
//  Ultrasync grid, the same Life micro-variation and the same Level. There is no second note
//  path to keep in step with the first.
//
//  A generator that emitted `Note`s directly would have been shorter to write and wrong: it
//  would have to re-implement all four of those, and would drift from them the first time one
//  changed. This app has already paid for a parallel path once (the mixer faders that could
//  not be heard because a second stage overwrote their amplitude, #177).
//
//  Not an arpeggiator, and the difference is the point. `BreathArp` walks the notes of a
//  CHORD. This walks the SURFACE — x is a scale degree across one octave, y is the octave
//  band — so what it plays is whatever the field would have played under a hand moving that
//  way. The two are meant to become one control with a mode (founder: "Vielleicht ist der arp
//  auch eine eigene Kategorie und könnte ein komplexes bedienelement werden"); keeping them
//  as separate pure cores is what makes that merge a UI decision rather than a rewrite.
//
//  Pure, Foundation-only, deterministic from (step, params, seed). No audio, no state, no
//  clock: the caller owns the tick. That is what makes the movement testable at all — the
//  shape of a wander is exactly the kind of thing that looks right in code and sounds like a
//  stuck note on a device.
//
//  ⚠️ NOT REACHABLE YET. Nothing constructs this as of the commit that introduced it — the
//  wiring to the voice and its control surface are the next slice. Said plainly here because
//  this repo has repeatedly been misled by cores that read as shipped (see the CLAUDE.md
//  "doors" paragraph); if you are reading this and there is still no caller, that is the gap.
//

import Foundation

public enum FieldAutoPlay {

    /// How the point travels across the surface. Deliberately few and each audibly distinct —
    /// a menu of eight subtly different wanders is the "more options that sound the same"
    /// failure this project has already hit twice (#81, #125).
    public enum Motion: String, CaseIterable, Sendable, Codable {
        /// Climbs, then jumps back — an ascending run.
        case rise
        /// The mirror of `rise`.
        case fall
        /// Up and back down without a jump: the most continuous, and the default.
        case pendulum
        /// A bounded seeded random walk — moves without a pattern the ear can predict.
        case drift
        /// Does not travel. How a player parks on one note and shapes it with everything
        /// else. NOT a slow wander — exactly still.
        case hold
    }

    /// A generated contact on the surface. Same three quantities a real finger supplies, in
    /// the same units, so the consumer cannot tell the difference (and must not).
    public struct Touch: Equatable, Sendable {
        /// 0 = left edge … 1 = right edge. Scale degree across one octave.
        public var x: Float
        /// 0 = bottom … 1 = top. Octave band.
        public var y: Float
        /// 0…1, as `TouchPitchMap.velocity` would have produced from a real contact.
        public var velocity: Float

        public init(x: Float, y: Float, velocity: Float) {
            self.x = x
            self.y = y
            self.velocity = velocity
        }
    }

    /// Every dial the player gets. Grouped as WHERE (centre/span/band/bandDrift), WHEN
    /// (density/periodSteps), HOW (motion) and HOW MANY (voices).
    public struct Params: Equatable, Sendable, Codable {
        public var motion: Motion
        /// How many of the grid cells fire, 0…1. **0 is silence**, not "a few" — this thing
        /// runs unattended, so the user cannot stop it by taking a hand away.
        public var density: Float
        /// How much of the surface the travel covers, 0…1. 0 collapses onto `centre`.
        public var span: Float
        /// Where the travel is centred, 0…1.
        public var centre: Float
        /// Which octave band it sits in, 0…1.
        public var band: Float
        /// How far it wanders vertically, 0…1. Deliberately on a slower cycle than the
        /// horizontal travel, so the two do not lock into one diagonal line.
        public var bandDrift: Float
        /// Simultaneous points — a chord under a hand that is not there.
        public var voices: Int
        /// Grid cells in one full traverse. Bigger = slower sweep at the same tempo.
        public var periodSteps: Int

        public init(motion: Motion = .pendulum, density: Float = 0.5, span: Float = 0.6,
                    centre: Float = 0.5, band: Float = 0.5, bandDrift: Float = 0.2,
                    voices: Int = 1, periodSteps: Int = 16) {
            self.motion = motion
            self.density = density
            self.span = span
            self.centre = centre
            self.band = band
            self.bandDrift = bandDrift
            self.voices = voices
            self.periodSteps = periodSteps
        }

        /// Additive decode (law 9), so a Params saved before a dial existed loads with that
        /// dial's default instead of throwing the whole setting away.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Params()
            // `?? nil` rather than a bare `decodeIfPresent`: a raw-value enum whose stored
            // case no longer exists throws `dataCorrupted`, which `decodeIfPresent` does NOT
            // absorb. Precedent: `Timeline.builtinInstrument`.
            motion = ((try? c.decodeIfPresent(Motion.self, forKey: .motion)) ?? nil) ?? d.motion
            density = (try? c.decode(Float.self, forKey: .density)) ?? d.density
            span = (try? c.decode(Float.self, forKey: .span)) ?? d.span
            centre = (try? c.decode(Float.self, forKey: .centre)) ?? d.centre
            band = (try? c.decode(Float.self, forKey: .band)) ?? d.band
            bandDrift = (try? c.decode(Float.self, forKey: .bandDrift)) ?? d.bandDrift
            voices = (try? c.decode(Int.self, forKey: .voices)) ?? d.voices
            periodSteps = (try? c.decode(Int.self, forKey: .periodSteps)) ?? d.periodSteps
        }
    }

    /// Hard ceiling on simultaneous points. These become note-ons: an absurd `voices` value
    /// from a corrupted preset or a future bio mapping must be CAPPED, never honoured.
    public static let maxVoices = 8

    // MARK: - The generator

    /// The contacts to play at grid cell `step`. Empty when the cell does not fire.
    ///
    /// - Parameters:
    ///   - step: grid cell index from the caller's clock. Negative values are folded, not
    ///     rejected — a caller counting from a bar boundary can legitimately go below zero.
    ///   - params: the dials.
    ///   - seed: makes `.drift` reproducible. The other motions are fixed curves and ignore
    ///     it, which is asserted rather than assumed.
    public static func touches(atStep step: Int, params: Params, seed: UInt64) -> [Touch] {
        let voices = Swift.min(maxVoices, params.voices)
        guard voices > 0 else { return [] }

        let density = clamp01(params.density)
        guard density > 0 else { return [] }

        let period = Swift.max(1, params.periodSteps)
        // Fold negatives into the period so a caller may count from anywhere.
        let cell = ((step % period) + period) % period

        guard fires(cell: cell, density: density, period: period) else { return [] }

        let span = clamp01(params.span)
        let centre = clamp01(params.centre)
        let phase = travel(motion: params.motion, cell: cell, period: period, seed: seed)

        // Vertical wander on a DELIBERATELY different period (×3, prime-ish against the
        // horizontal one) so x and y do not trace a single diagonal — the visual and audible
        // tell of a lazy 2D generator.
        let bandPhase = triangle(Float(((step % (period * 3)) + period * 3) % (period * 3))
                                 / Float(period * 3))
        let y = clamp01(params.band + (bandPhase - 0.5) * clamp01(params.bandDrift))

        return (0..<voices).map { voice in
            // Voices are offset ACROSS the span, so more than one is a chord rather than the
            // same note stacked N times at N times the level. With span 0 they collapse onto
            // the centre — correct: that setting means "one column", and the test pins it.
            let offset = voices == 1 ? 0 : (Float(voice) / Float(voices - 1) - 0.5)
            let x = clamp01(centre + (phase - 0.5) * span + offset * span * 0.5)
            return Touch(x: x, y: y, velocity: velocity(cell: cell, period: period))
        }
    }

    // MARK: - Pure pieces

    /// Which cells fire, spread evenly rather than clustered. Reuses the Euclidean rule
    /// `BreathArp` already uses (`(i * active) % steps < active`) INSTEAD of a probability
    /// roll: an even spread is what a player hears as a rate, where a dice roll at the same
    /// average is heard as stumbling.
    ///
    /// Density 1 must fire every cell and density 0 must fire none, so `active` is rounded
    /// from the full range and the zero case is handled by the caller before we get here.
    static func fires(cell: Int, density: Float, period: Int) -> Bool {
        let active = Int((density * Float(period)).rounded())
        guard active > 0 else { return false }
        guard active < period else { return true }
        return BreathArp.isActive(cell, active: active, steps: period)
    }

    /// 0…1 position within the traverse, before centre and span are applied.
    static func travel(motion: Motion, cell: Int, period: Int, seed: UInt64) -> Float {
        let t = Float(cell) / Float(Swift.max(1, period))
        switch motion {
        case .rise:     return t
        case .fall:     return 1 - t
        case .pendulum: return triangle(t)
        case .hold:     return 0.5
        case .drift:
            // A bounded walk recomputed from the cell index rather than carried in state:
            // this type is a pure function of (step, params, seed), so a caller may ask for
            // any cell in any order — a UI scrub, a test, a re-render — and get the same
            // answer. A stateful walk would silently depend on call order.
            var rng = SeededRNG(seed: seed &+ 0x4649454C_44000000)   // "FIELD"
            var value: Float = 0.5
            for _ in 0...cell {
                value = clamp01(value + (rng.unit() - 0.5) * 0.35)
            }
            return value
        }
    }

    /// Symmetric 0→1→0 over the cycle.
    static func triangle(_ t: Float) -> Float {
        let p = t.isFinite ? t - t.rounded(.down) : 0
        return p < 0.5 ? p * 2 : (1 - p) * 2
    }

    /// Downbeat cells hit a little harder — the difference between a player and a metronome.
    /// Kept small and deterministic; the expressive micro-variation belongs to Life, which
    /// already applies on the touch path this feeds.
    static func velocity(cell: Int, period: Int) -> Float {
        let beat = Swift.max(1, period / 4)
        return cell % beat == 0 ? 0.78 : 0.62
    }

    /// NaN-safe by argument order: `Swift.max(0, x)` returns 0 for NaN, `Swift.max(x, 0)`
    /// returns NaN. This app has shipped permanent silence from getting that backwards
    /// (CLAUDE.md, "Argument order in max/min decides NaN behaviour").
    static func clamp01(_ v: Float) -> Float {
        Swift.min(1, Swift.max(0, v.isFinite ? v : 0))
    }
}
