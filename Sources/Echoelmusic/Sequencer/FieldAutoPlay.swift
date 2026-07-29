//
//  FieldAutoPlay.swift
//  Echoelmusic — Sequencer
//
//  THE FIELD PLAYING ITSELF (founder 2026-07-29: "Es soll auch eine Möglichkeit geben wie
//  der Synth selbst spielt ohne das man Touch bedienen muss. Natürlich mit mehreren
//  Parametern").
//
//  THE ONE DESIGN DECISION, and everything else follows from it: this emits POSITIONS on the
//  play surface, not notes. A generated touch is a touch — it is meant to enter the surface at
//  the same place a finger does, so key-quantisation, the Ultrasync grid, the Life
//  micro-variation and the Level all apply to it without a second note path existing.
//
//  ⚠️ THAT IS THE INTENT, NOT YET THE FACT — but the gap is SMALLER than the first two
//  versions of this paragraph claimed, and both were wrong in the same direction. The
//  DECISION cores are already reusable and a generated touch can enter all of them today:
//    · Ultrasync — `TouchQuantizer.plan(forTick:index:seed:)` (public; the view only calls it)
//    · Life      — `TouchPitchMap.microVariation(noteIndex:depth:)` (public static)
//    · Level     — not in the touch path at all: it is a gain on the shared voice
//                  (`touchVoice.setGain` from `StudioDefaultKeys.touchLevel`, EchoelmusicApp),
//                  so anything routed into that voice inherits it with no hoist whatsoever.
//  What IS private is the DISPATCH in `TouchInstrumentUIView.sound(pitch:velocity:…)`: the
//  `Task.sleep` delay/echo scheduling, the lateness floor, the pending-note bookkeeping, and
//  the `noteCounter` that feeds `microVariation`. That dispatch — not the decisions — is what
//  the wiring slice must hoist or deliberately duplicate.
//
//  Said this precisely because the previous wording ("that hoist IS the slice") SIZED THE WORK
//  WRONGLY: it sent the next session off to hoist three things, two of which were already
//  hoisted and one of which was never in that method. A correction that is itself inaccurate
//  is worse than the claim it replaced, because it arrives wearing the authority of a fix.
//
//  A generator that emitted `Note`s directly would have been shorter to write and wrong for the
//  same reason: it would re-implement all four and drift from them the first time one changed.
//  This app has already paid for a parallel path once (the mixer faders that could not be heard
//  because a second stage overwrote their amplitude, #177).
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
//  REACHABLE, and here is the exact chain, because "wired" and "reachable" are the two things
//  this repo keeps conflating (see the CLAUDE.md "doors" paragraph — a slot with a setter is
//  not a door until the parent that renders it is itself reachable):
//    Field chip → `EchoelStudioView.visualPanel` → `touchSoundSection` → `fieldSelfPlaySection`
//    → `field.autoPlay.*` (StudioDefaultKeys) → `FloatingVisualWindow.fieldAutoPlay`
//    → `TouchInstrumentView(autoPlay:)` → `TouchInstrumentUIView`'s display-link clock
//    → `sound(...)`, the same dispatch a finger uses.
//  Default is OFF (`field.autoPlay.motion` == ""), and that is a stored state rather than the
//  absence of one: a generator that runs unattended must not be inherited from an update.
//
//  ⚠️ ONE REAL LIFETIME LIMIT, written here because it is discovered otherwise: self-play runs
//  only while the play surface is MOUNTED, i.e. while the floating visual window is on screen.
//  Closing that window stops it. Making it survive a closed window means an app-level driver
//  and a second note path — a separate decision, not a bug.
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
        /// A bounded seeded walk — moves without a shape the ear can name.
        ///
        /// It REPEATS every traverse, and that is deliberate rather than a shortcoming: the
        /// walk is recomputed from the cell index (see `travel`), so the same figure returns
        /// each period. A walk keyed on absolute step would never repeat, and would also cost
        /// one RNG draw per elapsed step forever — a generator that gets slower the longer the
        /// performance runs. What this gives is an irregular FIGURE, not noise. Say it that way
        /// to a player; the original wording promised unpredictability it does not deliver.
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
        ///
        /// ⚠️ THE PITCH EFFECT HAS A THRESHOLD, and it is not obvious from the number. `y`
        /// selects one of THREE octave bands (`TouchPitchMap`: `min(2, Int(y * 3))`), so the
        /// wander must span more than 1/3 to cross a boundary and change the octave at all.
        /// The default 0.2 centred at band 0.5 stays inside 0.4…0.6 — entirely within the
        /// middle band. That is NOT a dead default: `y` is also the vertical position a
        /// finger's light drops at in the field, so ONCE WIRED, sub-threshold values will move
        /// the VISUAL and leave the pitch alone — a musically sensible place to start. (Stated
        /// as intent: nothing consumes this generator yet, and the ripple itself is private to
        /// the touch view and skipped under Reduce Motion.) Above ~0.34 it
        /// starts changing octaves. Documented because a control whose first third does
        /// nothing audible reads as broken unless you say what it is doing instead.
        public var bandDrift: Float
        /// Simultaneous points — a chord under a hand that is not there.
        public var voices: Int
        /// Grid cells in one full traverse. Bigger = slower sweep at the same tempo.
        /// Clamped to `maxPeriodSteps` on both decode and use — see that constant.
        public var periodSteps: Int

        /// Format stamp (#189), same shape as `MoodPreset`: the ENCODER writes it; a future
        /// migration that cannot be handled additively (a renamed dial, a changed unit) reads
        /// the file's own value into a local inside `init(from:)`. Stamping costs one line
        /// now; adding it after the first saves are in the wild does nothing for those saves.
        public static let currentSchemaVersion = 1

        /// ⚠️ Deliberately NOT assigned from the payload on decode — it stays at current, so
        /// two functionally identical Params never compare unequal just because one came off
        /// disk. Same reasoning as `MoodPreset.schemaVersion`.
        public private(set) var schemaVersion: Int = Params.currentSchemaVersion

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
            // `try?` rather than a bare `decodeIfPresent`: a raw-value enum whose stored case
            // no longer exists throws `dataCorrupted`, and `decodeIfPresent` does NOT absorb a
            // throw — it only absorbs ABSENCE. Precedent: `Timeline.builtinInstrument`.
            // (The first version wrapped this in `?? nil` and explained the wrap; under
            // SE-0230 `try?` already flattens the double optional, so the wrap was a no-op
            // and its explanation was wrong. The DEFENCE was right, the reasoning was not.)
            motion = (try? c.decode(Motion.self, forKey: .motion)) ?? d.motion
            density = (try? c.decode(Float.self, forKey: .density)) ?? d.density
            span = (try? c.decode(Float.self, forKey: .span)) ?? d.span
            centre = (try? c.decode(Float.self, forKey: .centre)) ?? d.centre
            band = (try? c.decode(Float.self, forKey: .band)) ?? d.band
            bandDrift = (try? c.decode(Float.self, forKey: .bandDrift)) ?? d.bandDrift
            voices = (try? c.decode(Int.self, forKey: .voices)) ?? d.voices
            // Clamped at the BOUNDARY as well as at use: a corrupted or hand-edited payload
            // carrying `Int.max` would otherwise sit in memory as a legal-looking value and
            // trap the first time something multiplied it.
            let steps = (try? c.decode(Int.self, forKey: .periodSteps)) ?? d.periodSteps
            periodSteps = Swift.min(FieldAutoPlay.maxPeriodSteps, Swift.max(1, steps))
        }
    }

    /// Hard ceiling on simultaneous points. These become note-ons: an absurd `voices` value
    /// from a corrupted preset or a future bio mapping must be CAPPED, never honoured.
    public static let maxVoices = 8

    /// Hard ceiling on the traverse length, and this one is a CRASH GUARD, not taste.
    ///
    /// Three things downstream are not safe for an arbitrary `Int`:
    ///   • `period * 3` (the vertical wander's slower cycle) — Swift TRAPS on overflow, so a
    ///     `periodSteps` near `Int.max` is a hard crash, not a strange sound.
    ///   • the `.drift` walk iterates once per cell (`for _ in 0...cell`), so a millionfold
    ///     period is a millionfold RNG loop on whatever thread called it.
    ///   • `Float(cell) / Float(period)` loses meaning long before either of those.
    ///
    /// 1024 cells is already ~64 bars of sixteenths — far past any musical traverse, and the
    /// exact reason the ceiling can be this generous and still be a real guard.
    public static let maxPeriodSteps = 1024

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

        // Clamped HERE as well as in the decoder: `Params` is a public struct with a
        // memberwise init, so a caller (a bio mapping, a UI, a test) can hand us any Int
        // without ever going through a decoder. The guard belongs where the arithmetic is.
        let period = Swift.min(maxPeriodSteps, Swift.max(1, params.periodSteps))
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

    // MARK: - The clock decision

    /// Which cell of the traverse a musical TICK falls in. The caller keeps the last value
    /// it fired and asks for touches when this changes — that is the whole "when do I play"
    /// decision, and it lives here as a pure function so it can be tested instead of being
    /// discovered as a stuck or double-firing note on a device.
    ///
    /// TWO THINGS THIS GUARDS, both of which trap or misbehave if written inline:
    ///
    /// • **Division by zero.** `ticksPerCell` will come from a grid setting, and an integer
    ///   division by zero in Swift is a hard trap, not a NaN. Clamped to ≥ 1 here so no
    ///   caller has to remember.
    /// • **Negative ticks floor, they do not truncate.** Swift's `/` rounds toward zero, so
    ///   `-1 / 4 == 0` — the same cell as tick 0, making the cell straddling the origin twice
    ///   as wide as every other and swallowing one fire. Floor division makes cells uniformly
    ///   `ticksPerCell` wide on both sides of zero.
    ///
    ///   DEFENSIVE, not a live scenario — and worth saying precisely, because the first
    ///   version of this comment asserted that "a transport counting from a bar line can
    ///   legitimately hand over a negative tick". It cannot: `Transport.currentTick()` goes
    ///   through `StepTickMath`, which clamps the step to ≥ 0. No clock in this repo produces
    ///   a negative tick today. The guard stays because this is a `public` function taking a
    ///   plain `Int` from any future caller, and because floor is simply the correct meaning
    ///   of "which cell" — but it is insurance, not a bug being fixed.
    ///
    /// Deliberately NOT folded into `periodSteps` here — this answers "which cell of the
    /// clock", `touches(atStep:)` answers "what does that cell play". Keeping them separate
    /// is what lets the caller detect a CHANGE; a pre-folded value repeats.
    public static func cell(forTick tick: Int, ticksPerCell: Int) -> Int {
        let per = Swift.max(1, ticksPerCell)
        let q = tick / per
        return (tick < 0 && tick % per != 0) ? q - 1 : q
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
    ///
    /// The floor is 2, not 1, and that is the whole fix. INTEGER division: `period / 4` is 0
    /// for periods 1–3 and 1 for 4–7, and the old `max(1, …)` floored all of them to 1 — and
    /// `cell % 1 == 0` is true for EVERY cell, so the accent silently vanished and every note
    /// came out at 0.78. A short traverse is exactly where a player still expects to hear a
    /// downbeat, so the degenerate case was the one that mattered.
    ///
    /// ⚠️ THE BROKEN RANGE IS 1–7, NOT ≤4. The first version of this note said "4 or less"
    /// and its test swept 2, 3, 4, 8, 16 — skipping 5, 6 and 7, which is precisely the half
    /// of the range the wrong number hid. So this floor changes behaviour at periods 5–7 as
    /// well; say so rather than repeating "nothing shipped changes", which is true only of
    /// the default. At period 16 the value is 4 exactly as before.
    static func velocity(cell: Int, period: Int) -> Float {
        let beat = Swift.max(2, period / 4)
        return cell % beat == 0 ? 0.78 : 0.62
    }

    /// NaN-safe by argument order: `Swift.max(0, x)` returns 0 for NaN, `Swift.max(x, 0)`
    /// returns NaN. This app has shipped permanent silence from getting that backwards
    /// (CLAUDE.md, "Argument order in max/min decides NaN behaviour").
    static func clamp01(_ v: Float) -> Float {
        Swift.min(1, Swift.max(0, v.isFinite ? v : 0))
    }
}
