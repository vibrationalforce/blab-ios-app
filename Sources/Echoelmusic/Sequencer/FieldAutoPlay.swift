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
//  Five of the six motions walk the SURFACE — x is a scale degree across one octave, y is the
//  octave band — so what they play is whatever the field would have played under a hand moving
//  that way. The SIXTH, `.arp`, walks a CHORD instead (#220 S3, founder: "Vielleicht ist der arp
//  auch eine eigene Kategorie und könnte ein komplexes bedienelement werden"): the merge this
//  paragraph used to describe as future work has happened, as ONE motion slot rather than a
//  second self-play surface. The walk itself lives in `ArpFigure` (pure, its own tests), and this
//  file only decides WHEN it steps and WHERE on the surface that lands.
//
//  ⚠️ Choosing `.arp` therefore turns the travelling OFF — one slot, one behaviour. Say that to
//  a player rather than leaving them to discover it, and note that `centre`, `span` and `voices`
//  do not apply on that motion at all (the panel hides those rows; see the `.arp` case).
//  `BreathArp` is untouched and is NOT this: its live half is the Euclidean density rule that
//  `fires` below reuses.
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
        /// Walks the tones of a CHORD instead of a path across the surface (#220 S3, founder
        /// 2026-07-29: *"Vielleicht ist der arp auch eine eigene Kategorie"*).
        ///
        /// ⚠️ IT IS A DIFFERENT KIND OF MOTION FROM THE OTHER FIVE, and pretending otherwise is
        /// how it would become a lying control. The other five are CURVES: `travel` returns a
        /// 0…1 position and `centre`/`span`/`voices` then place it. The arp has no curve — its
        /// x is a specific scale-degree CELL, and nudging that cell off its centre by a span or
        /// an offset would produce a wrong note rather than a wider gesture. So on this motion
        /// `centre`, `span` and `voices` are not applied at all, and the panel hides those rows
        /// rather than leaving three dials that do nothing (`EchoelStudioView.fieldSelfPlayFields`).
        /// `density` sets the RATE and `band`/`bandDrift` the register.
        ///
        /// ⚠️ SINCE #253 A2 THE ARP'S RHYTHM IS `Params.arpRhythm`, not a curve: which cells sound,
        /// how hard and how long all come from `RoleRhythm` — six named characters (driving,
        /// hypnotic, dynamic, sparse, syncopated, flowing), which is what the founder asked for.
        /// `density` stays the ONE rate dial and is fed into that type rather than duplicated.
        ///
        /// ⚠️ WHAT `periodSteps` DOES FOR THE ARP, restated because the previous version of this
        /// note is now half wrong. It is the arp's BAR: the rhythm's per-bar behaviour (`hypnotic`'s
        /// rotation, `dynamic`'s contour, `evolve`) advances once per traverse, and the "beat" the
        /// characters place their accents against is `periodSteps / 4`. It is therefore NOT a rate
        /// dial — the even-spread rule `(i · active) % period < active` with
        /// `active = round(density · period)` is scale-invariant in `period`, so at density 0.5 the
        /// notes fall every second cell whether the traverse is 8, 16 or 32. FOUR characters keep
        /// exactly that — `driving`, `dynamic`, `hypnotic` (a rotation of a scale-invariant set is
        /// still scale-invariant; an earlier version of this line miscounted it as three and left
        /// `hypnotic` out) and `flowing` ONLY while `evolve == 0`, since above 0 it flips individual
        /// cells and is no longer the plain spread. `sparse` and `syncopated` measure against the
        /// beat, so for those two the traverse DOES change which cells sound: `syncopated` at
        /// density 0.5 fires 4 of 8 cells at traverse 8 and 4 of 16 at traverse 16.
        ///
        /// One note per fired cell, never `voices` of them: an arpeggio is a chord played as a
        /// SEQUENCE. Stacking it would just be the chord, which the generative engine already
        /// plays.
        case arp
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
        /// How long the note should ring, as a fraction of ONE GRID CELL — or `nil` for
        /// "this motion has no opinion, use the surface's own default".
        ///
        /// ⚠️ `nil` IS THE POINT, not laziness (#253 A2). The five TRAVELLING motions never had a
        /// length: their notes ring for `TouchInstrumentUIView.staccatoSeconds` (0.18 s, a fixed
        /// wall-clock value). Defaulting this to `1` instead of `nil` would silently re-time all
        /// five — at 1/16 / 120 BPM a cell is 125 ms, so every travelling note would get SHORTER
        /// than it is today, on a slice that is supposed to change only the arp. `nil` says
        /// "unchanged" in a way a reader cannot mistake for a value.
        ///
        /// A fraction and not seconds, because this type never knows a tempo or a grid — the
        /// consumer multiplies by its own cell length, exactly as it already does for `x`/`y`
        /// against its own surface.
        public var gateFraction: Float?

        /// How much LATER than its cell's own tick the note should sound, as a fraction of ONE
        /// GRID CELL — or `nil` for "this motion has no opinion, it lands on the grid".
        ///
        /// Positive only, in effect: negative would mean EARLIER than a moment that has already
        /// arrived, and a generated note is created at its cell edge with no look-ahead, so there
        /// is nothing to be early against. `pushDelaySeconds` therefore folds anything ≤ 0 to
        /// "on the grid" rather than pretending. No writer can produce a negative today either —
        /// the arp has no persisted `push` key and both character biases are positive
        /// (`syncopated` +0.12, `flowing` +0.05) — but the type is public and the guard belongs
        /// where the arithmetic is (#253 A2b).
        ///
        /// `nil` and not `0` for the same reason as `gateFraction`: the five travelling motions
        /// have no timing opinion, and a reader must not be able to mistake "unchanged" for a
        /// value that was chosen.
        public var pushFraction: Float?

        public init(x: Float, y: Float, velocity: Float,
                    gateFraction: Float? = nil, pushFraction: Float? = nil) {
            self.x = x
            self.y = y
            self.velocity = velocity
            self.gateFraction = gateFraction
            self.pushFraction = pushFraction
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
        /// generated note's light drops at in the field, so sub-threshold values move the
        /// VISUAL and leave the pitch alone — a musically sensible place to start. Above ~0.34
        /// it starts changing octaves. Documented because a control whose first third does
        /// nothing audible reads as broken unless you say what it is doing instead.
        ///
        /// ⚠️ That sentence was written as INTENT and was false for one commit: the driver
        /// sounded generated notes without touching the colour/ripple channels a finger uses,
        /// so sub-threshold drift moved nothing whatsoever. Review caught it; the driver now
        /// calls `showGeneratedNote`. Kept as a note because a doc promise about a SECOND
        /// subsystem is only true while that subsystem keeps its half — and the ripple is
        /// still skipped under Reduce Motion, which is correct and is not this promise.
        ///
        /// ⚠️ AND IT DOES NOT HOLD FOR `.arp` AT ALL (#220 S3). That motion's `y` comes from
        /// `ArpFigure.surfacePoint`, which returns the CENTRE of its register — so the light sits
        /// at one of `bandCount` fixed heights and a sub-threshold drift moves neither the octave
        /// nor the visual. The panel says so in its own words for that motion; this doc is the
        /// source of truth the panel is checked against, so the exception belongs here too.
        public var bandDrift: Float
        /// Simultaneous points — a chord under a hand that is not there.
        public var voices: Int
        /// Grid cells in one full traverse. Bigger = slower sweep at the same tempo.
        /// Clamped to `maxPeriodSteps` on both decode and use — see that constant.
        public var periodSteps: Int

        // MARK: The arp dials — read ONLY when `motion == .arp` (#220 S3)
        //
        // ⚠️ THREE OF THESE FOUR STILL HAVE NO WRITER, and saying which is the house rule rather
        // than a courtesy. `arpRhythm` GAINED one with #253 A7 — four `StudioDefaultKeys` written by
        // the Field panel's Rhythm / Note length / Accent / Evolve rows and folded back in by
        // `FloatingVisualWindow.fieldAutoPlay`. `arpOrder`, `arpOctaves` and `arpChordDegrees` are
        // still unreachable: nothing in `Sources/` sets them, so the arp always walks the stored
        // defaults below. Their keys and rows are #220 S5. Read THOSE three doc comments as "what
        // this dial WILL do", not as a control a player can reach.
        //
        // ⚠️ AND THE DEFAULTS ARE LOAD-BEARING EVEN WHERE A WRITER EXISTS. These are what the arp
        // SOUNDS LIKE for anyone who has not touched a row, so changing one changes the shipped
        // instrument — which is why `arpRhythm`'s default was picked to keep the fire pattern
        // identical to the pre-A2 Euclidean one rather than to be the type's own prettiest setting,
        // and why `TouchSurfaceStorageKeysTests` pins the A7 keys against THIS default rather than
        // against literals of its own.

        /// Which way the arp walks its chord.
        public var arpOrder: ArpFigure.Order
        /// Octave span of the arp walk, 1…`ArpFigure.maxOctaves`.
        ///
        /// ⚠️ THE SURFACE HAS A CEILING and this dial can reach it: `band` picks the base
        /// register, and a span that lifts past the top band SATURATES there — the highest
        /// octaves then repeat instead of rising (`ArpFigure.surfacePoint` documents why
        /// saturating beats folding down, and why the walk is not quietly re-based lower). With
        /// the shipped three-band surface the condition for every octave to be audible is
        /// `baseBand + arpOctaves - 1 + the chord's own carry < 3`. The default 1 is inside it.
        public var arpOctaves: Int
        /// The chord as SCALE-DEGREE indices, not semitones — `[0, 2, 4]` means the 1st, 3rd and
        /// 5th degrees of whatever key the take is in, so the walk is always in key.
        ///
        /// ⚠️ NOT "always a triad": that holds only in a seven-degree scale. In `chromatic` those
        /// degrees are a whole-tone cluster, in `pentatonicMinor` root/fourth/flat-seventh. In key
        /// either way, but do not describe it to a player as root-third-fifth.
        ///
        /// Negatives are dropped and duplicates collapse inside `ArpFigure`; an empty result is
        /// SILENCE, not a substituted root.
        public var arpChordDegrees: [Int]

        /// WHICH RHYTHM the arp walks its chord in (#253 A2, founder 2026-07-30: *"Alle
        /// Soundrubriken von Pads, Bass bis arp etc. brauchen noch verschiedene Rhythmus Regler …
        /// interessante, treibende, hypnotische, dynamische"*).
        ///
        /// ⛔ ITS `density` IS IGNORED, and this is the one thing to know before touching it. The
        /// Field already HAS a rate dial — `density` above, doored and persisted — and two controls
        /// over one musical dimension is the collision `RoleRhythm`'s own header decides: the
        /// per-role type wins for what it owns, and the rate stays the ONE existing dial. So
        /// `arpTouches` overwrites this copy's `density` with the Field's before asking, and a
        /// value stored here can never contradict what the player sees.
        ///
        /// What it DOES bring: the character (which cells fire and how the accent sits), the gate
        /// (note length as a fraction of a cell), the accent depth and `evolve`. `push` is carried
        /// but NOT YET HONOURED — see `arpTouches` for why displacing a generated onset is its own
        /// slice rather than a parameter pass.
        ///
        /// Default `.driving` with `evolve: 0`, chosen to keep this slice's change to the arp as
        /// small as it can honestly be: `driving` fires the plain even spread, the same rule
        /// `fires(cell:density:period:)` used. `flowing` (the type's own default) would have
        /// flipped cells at `evolve 0.2` and changed the figure outright.
        ///
        /// ⚠️ "THE SAME RULE" IS NOT "THE SAME SET", and the first version of this line claimed
        /// bit-for-bit identity, which is false in a reachable band. `RoleRhythm.spread` floors the
        /// active count at 1 for any density above 0 (its own doc explains why: a dial reading "on"
        /// that produces nothing is a lying control). The old `fires` returned `false` whenever
        /// `round(density · period)` rounded to 0. So for `0 < density < 1/(2 · period)` — e.g.
        /// traverse 16 at density 0.02, and the Density row does offer two decimals — the arp used
        /// to be silent forever and now sounds cell 0 once per traverse. That is an improvement,
        /// and the diff's own test encodes the floor; the identity claim was the untrue part.
        ///
        /// ⚠️ AND THE NOTE LENGTH IS THE BIG CHANGE, disclosed here with its magnitude because the
        /// previous wording ("only the LEVEL curve and the note length are new") was true and told
        /// nobody how much. Before A2 every arp note rang for a fixed `staccatoSeconds` = 180 ms.
        /// Now it is `gate × gateScale` of a CELL: on the default 1/16 grid at 120 BPM (125 ms per
        /// cell) that is `0.8 × 0.45 × 125` ≈ **45 ms** — about a quarter of the old length, and
        /// `driving` cannot reach 180 ms at all (that would be 1.44 cells, i.e. the old behaviour
        /// deliberately OVERLAPPED consecutive notes, which is what
        /// `TouchInstrumentUIView.scheduleSelfRelease`'s token guard exists to survive). A crisp
        /// detached arp is the musical intent of "treibend" and the reason the character exists —
        /// but it is a real change to the shipped instrument with no UI involved, so it is
        /// **NEEDS-FOUNDER-VERIFY**, not a silent default.
        public var arpRhythm: RoleRhythm.Params

        /// Format stamp (#189), same shape as `MoodPreset`: the ENCODER writes it; a future
        /// migration that cannot be handled additively (a renamed dial, a changed unit) reads
        /// the file's own value into a local inside `init(from:)`. Stamping costs one line
        /// now; adding it after the first saves are in the wild does nothing for those saves.
        public static let currentSchemaVersion = 1

        /// ⚠️ Deliberately NOT assigned from the payload on decode — it stays at current, so
        /// two functionally identical Params never compare unequal just because one came off
        /// disk. Same reasoning as `MoodPreset.schemaVersion`.
        public private(set) var schemaVersion: Int = Params.currentSchemaVersion

        /// The arp dials sit LAST and are defaulted, so every existing call site — the window's
        /// `fieldAutoPlay`, every test — compiles and behaves byte-identically. Additive by
        /// construction, and that is what makes this slice reversible.
        public init(motion: Motion = .pendulum, density: Float = 0.5, span: Float = 0.6,
                    centre: Float = 0.5, band: Float = 0.5, bandDrift: Float = 0.2,
                    voices: Int = 1, periodSteps: Int = 16,
                    arpOrder: ArpFigure.Order = .up, arpOctaves: Int = 1,
                    arpChordDegrees: [Int] = [0, 2, 4],
                    arpRhythm: RoleRhythm.Params = RoleRhythm.Params(character: .driving,
                                                                     evolve: 0)) {
            self.motion = motion
            self.density = density
            self.span = span
            self.centre = centre
            self.band = band
            self.bandDrift = bandDrift
            self.voices = voices
            self.periodSteps = periodSteps
            self.arpOrder = arpOrder
            self.arpOctaves = arpOctaves
            self.arpChordDegrees = arpChordDegrees
            self.arpRhythm = arpRhythm
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
            // The arp dials (#220 S3). `arpOrder` gets the same `try?` as `motion` and for the
            // same reason — it is a raw-value enum, so a stored case that a later build removes
            // THROWS `dataCorrupted` rather than reading as absent.
            arpOrder = (try? c.decode(ArpFigure.Order.self, forKey: .arpOrder)) ?? d.arpOrder
            let octaves = (try? c.decode(Int.self, forKey: .arpOctaves)) ?? d.arpOctaves
            arpOctaves = Swift.min(ArpFigure.maxOctaves, Swift.max(1, octaves))
            // Capped at the boundary as well: a decoded array must never size an allocation
            // inside `ArpFigure.permutation`, and a "chord" of thousands of tones is corruption
            // rather than a request. `ArpFigure.sanitize` caps too — this stops the oversized
            // array from sitting in memory looking legitimate in the meantime.
            let chord = (try? c.decode([Int].self, forKey: .arpChordDegrees)) ?? d.arpChordDegrees
            arpChordDegrees = Array(chord.prefix(ArpFigure.maxChordTones))
            // `RoleRhythm.Params` has its OWN additive, clamping `init(from:)`, so a nested
            // `try?` here is only the absent-whole-object case — an arp saved before #253 A2.
            arpRhythm = (try? c.decode(RoleRhythm.Params.self, forKey: .arpRhythm)) ?? d.arpRhythm
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

    /// Ceiling on how many octave bands a caller may claim the surface has.
    ///
    /// A CRASH GUARD, found by review rather than by taste: `bandCount` is a public, defaulted
    /// parameter, and the arp derives its base band with `Int(y * Float(bands))`. `Float(Int.max)`
    /// rounds to 2^63 and converting that back to `Int` TRAPS. 16 is far past any surface anyone
    /// would build (the shipped one has three) and still a real bound.
    public static let maxSurfaceBands = 16

    // MARK: - The generator

    /// The contacts to play at grid cell `step`. Empty when the cell does not fire.
    ///
    /// - Parameters:
    ///   - step: grid cell index from the caller's clock. Negative values are folded, not
    ///     rejected — a caller counting from a bar boundary can legitimately go below zero.
    ///   - params: the dials.
    ///   - seed: makes `.drift` and `.arp`'s `.random` order reproducible. The other motions are
    ///     fixed curves and ignore it, which is asserted rather than assumed.
    ///   - degreesPerOctave: scale degrees per octave of the key the CONSUMER will map with, and
    ///     read ONLY by `.arp`. Defaulted so this slice touches no existing call site; the one
    ///     production caller passes `key.degreesPerOctave` of the very key it then hands to
    ///     `TouchPitchMap.pitch` (`TouchInstrumentView`). Passing a different number is not a
    ///     crash, it is a wrong DEGREE that stays inside the key — the invisible kind.
    ///   - bandCount: octave bands the surface spans, likewise `.arp`-only. The caller passes
    ///     `TouchPitchMap.octaveBands.count`; the default matches the shipped surface.
    public static func touches(atStep step: Int, params: Params, seed: UInt64,
                               degreesPerOctave: Int = 7, bandCount: Int = 3) -> [Touch] {
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

        // Vertical wander on a DELIBERATELY different period (×3, prime-ish against the
        // horizontal one) so x and y do not trace a single diagonal — the visual and audible
        // tell of a lazy 2D generator.
        let bandPhase = triangle(Float(((step % (period * 3)) + period * 3) % (period * 3))
                                 / Float(period * 3))
        let y = clamp01(params.band + (bandPhase - 0.5) * clamp01(params.bandDrift))

        // The arp is not a curve, so it leaves the travel/span/centre path entirely — see the
        // `.arp` case's own note for why bending its x would be a wrong note rather than a wider
        // gesture. It keeps `y` (register + its slow wander) and brings its own rhythm.
        //
        // ⛔ IT BRANCHES ABOVE THE `fires` GUARD, and moving it there was the whole point of
        // #253 A2 rather than an accident of ordering. `RoleRhythm` decides which cells the arp
        // sounds, and leaving the Euclidean guard above the branch would INTERSECT the two rules:
        // the arp would only sound where BOTH agree.
        //
        // THE CASE THAT FORCES THE MOVE IS `hypnotic`, AND IT IS WORSE THAN "LOSES SOME ROTATION"
        // (which is what the first version of this comment said). Its figure is the base spread
        // ROTATED BY THE BAR INDEX: at density 0.5, traverse 16, bar `b` it wants the cells whose
        // `(position − b)` is even. For every ODD bar that is the odd cells — and the Euclidean base
        // is the even ones, so the intersection is EMPTY. The arp would go completely silent on
        // every second bar. `sparse` (density 0.3, traverse 16: cells 8 and 12 drop out) and
        // `flowing` with `evolve > 0` lose notes more mildly.
        //
        // ⚠️ AND THE OTHER EXAMPLE THAT USED TO STAND HERE WAS WRONG IN THE OPPOSITE DIRECTION:
        // `syncopated` would NOT "go nearly silent". At density 0.5, traverse 16 its cells
        // {2,6,10,14} are a SUBSET of the even base, so intersecting would change nothing at all;
        // at density 0.75 it merely halves. Naming the mild case as the severe one and the severe
        // one as mild is the kind of correction this file elsewhere calls worse than the claim it
        // replaced, so both are stated as measured.
        //
        // The two guards above this (`voices`, `density`) stay where they are: both mean silence
        // for every motion, arp included.
        if params.motion == .arp {
            return arpTouches(step: step, cell: cell, period: period, density: density,
                              y: y, params: params, seed: seed,
                              degreesPerOctave: degreesPerOctave, bandCount: bandCount)
        }

        guard fires(cell: cell, density: density, period: period) else { return [] }

        let span = clamp01(params.span)
        let centre = clamp01(params.centre)
        let phase = travel(motion: params.motion, cell: cell, period: period, seed: seed)

        return (0..<voices).map { voice in
            // Voices are offset ACROSS the span, so more than one is a chord rather than the
            // same note stacked N times at N times the level. With span 0 they collapse onto
            // the centre — correct: that setting means "one column", and the test pins it.
            let offset = voices == 1 ? 0 : (Float(voice) / Float(voices - 1) - 0.5)
            let x = clamp01(centre + (phase - 0.5) * span + offset * span * 0.5)
            return Touch(x: x, y: y, velocity: velocity(cell: cell, period: period))
        }
    }

    // MARK: - The arp

    /// The ONE contact an arp cell plays, or none when its rhythm rests or the chord is empty.
    ///
    /// ⛔ THE WALK ADVANCES PER SOUNDED NOTE, NOT PER CELL, and that is the whole reason this is
    /// not two lines inside `touches`. Using the cell index as the walk position looks right and
    /// is wrong: at density 0.5 the arp would then skip every second chord tone, so `ArpFigure`'s
    /// one guarantee — every tone sounds exactly once per cycle — would be silently false, and an
    /// "up" figure would come out full of holes. What a player expects, and what hardware arps
    /// do, is one step of the pattern per RATE tick. So the index is the count of cells that have
    /// SOUNDED: the ones before this cell in the traverse, plus a traverse's worth for each
    /// completed traverse.
    ///
    /// WHICH cells sound is `RoleRhythm`'s decision since #253 A2 — the founder asked for
    /// *"verschiedene Rhythmus Regler … interessante, treibende, hypnotische, dynamische"* per
    /// sound role, and the arp is the first role bound. That replaced the plain Euclidean
    /// `fires(cell:density:period:)` here (the travelling motions still use it), and it also
    /// brings the LEVEL and the note LENGTH: `Touch.velocity` and `Touch.gateFraction` are the
    /// rhythm's, not a curve's. The rate is still the Field's own Density dial — see
    /// `Params.arpRhythm` for why that copy's `density` is overwritten rather than read.
    ///
    /// Cost, stated properly because the first version understated it by half and mis-described the
    /// work: `1 + 2 · period` calls to `RoleRhythm.hit` per SOUNDED cell — the guard once, then two
    /// prefix passes — so up to ~2049 at `maxPeriodSteps`. And `hit` is not a cheap modulo test: it
    /// builds a `SeededRNG` every time and on `dynamic` calls `sinf`, all to be compared against
    /// `nil`. Still comfortably free at the real rates (the UI caps the traverse at 64 and the
    /// fastest grid is 1/16 triplets, so ~4k calls a second at 300 BPM, on the main thread, only
    /// when the grid CELL changes — never per frame). If a later slice makes the traverse big or
    /// the grid finer, the fix is a `RoleRhythm` predicate that skips the accent maths, not a cache.
    ///
    /// Wrapping arithmetic on purpose: `traverse * firedPerTraverse` would TRAP for an absurd
    /// `step`, and a trap on the self-play path is the worst outcome available. A wrap merely
    /// lands on a different position of the same walk — `ArpFigure` folds any `Int` by flooring.
    static func arpTouches(step: Int, cell: Int, period: Int, density: Float, y: Float,
                           params: Params, seed: UInt64,
                           degreesPerOctave: Int, bandCount: Int) -> [Touch] {
        // ONE traverse = one BAR for the rhythm, which is the honest mapping: `periodSteps` is
        // "how many cells before the pattern comes round again", and that is what a bar is to a
        // rhythm generator. It is also what makes `hypnotic`'s per-bar rotation and `dynamic`'s
        // per-bar contour land on the traverse the player set rather than on some other unit.
        let traverse = ArpFigure.floorDiv(step, period)
        // The Field's own Density dial is the ONE rate control (see `Params.arpRhythm`), so the
        // stored copy's `density` is overwritten rather than consulted. Doing it here and not in
        // the UI means a hand-edited or bio-written value cannot contradict the visible dial.
        var rhythm = params.arpRhythm
        rhythm.density = density

        guard let beat = RoleRhythm.hit(bar: traverse, cell: cell, cellsPerBar: period,
                                        params: rhythm, seed: seed) else { return [] }

        let firedPerTraverse = arpFiredCount(before: period, bar: traverse,
                                             rhythm: rhythm, period: period, seed: seed)
        let firedBefore = arpFiredCount(before: cell, bar: traverse,
                                        rhythm: rhythm, period: period, seed: seed)
        let index = traverse &* firedPerTraverse &+ firedBefore

        guard let walk = ArpFigure.step(atIndex: index,
                                        chordDegrees: params.arpChordDegrees,
                                        octaves: params.arpOctaves,
                                        order: params.arpOrder,
                                        seed: seed) else { return [] }

        // ⛔ TWO INPUTS DECIDE WHETHER THE `Int(...)` BELOW TRAPS, AND THE FIRST VERSION OF THIS
        // COMMENT ONLY CHECKED ONE. `y` is fine: `clamp01` is NaN-safe, so it is always 0…1. But
        // `bandCount` is a PUBLIC, DEFAULTED parameter that any caller may set — `Float(Int.max)`
        // rounds to 2^63 and `Int(2^63 as Float)` TRAPS. No shipping caller can reach it today
        // (`TouchPitchMap.octaveBands.count` is 3), which is exactly the kind of "cannot happen"
        // this file already refuses to rely on for `periodSteps` and `voices`: the guard belongs
        // where the arithmetic is. Ceiling rather than a precondition, for the same reason as
        // `maxPeriodSteps` — a corrupt input should sound wrong, not crash a performance.
        let bands = Swift.min(maxSurfaceBands, Swift.max(1, bandCount))
        let baseBand = Swift.min(bands - 1, Int(y * Float(bands)))
        let point = ArpFigure.surfacePoint(walk,
                                          degreesPerOctave: degreesPerOctave,
                                          bandCount: bands,
                                          band: baseBand)
        return [Touch(x: Float(point.x), y: Float(point.y),
                      velocity: beat.velocity, gateFraction: beat.gateFraction,
                      pushFraction: beat.pushFraction)]
        // ✅ `beat.pushFraction` IS CARRIED NOW (#253 A2b). What it must NOT do is travel through
        // ULTRASYNC, and the reason is UNCONDITIONAL: `TouchQuantizer.plan` returns `.play` the
        // moment `offset == 0` — which is every generated note, because the consumer hands it the
        // cell's own on-grid tick — and `.play` sounds IMMEDIATELY whatever tick it carries. So a
        // pushed tick could not delay anything at ANY tempo and at ANY `strength`. The consumer
        // therefore gives the onset its OWN scheduled delay (`pushDelaySeconds` →
        // `TouchInstrumentUIView`'s `pendingOn` discipline) and still hands Ultrasync the unpushed
        // tick. A future reader who "simplifies" that into one tick offset gets silence, not groove.
        //
        // ⚠️ AND BELOW ~75 BPM IT WOULD ALSO FLAM — stated second, because the first version of this
        // comment led with the flam and got the arithmetic wrong. It claimed a 0.12 push (14 ticks on
        // a 1/16 grid) "takes the `.playThenEcho` branch, i.e. a DOUBLED note", ignoring that
        // `sound(...)` raises the tolerance to 20 ms of real time: that is 19 ticks at 120 BPM, so 14
        // stays INSIDE it and `plan` answers `.play`. The 12-tick default only dominates the 20 ms
        // floor below ≈75 BPM, and only there would the echo actually fire. The conclusion never
        // depended on it; leading with the conditional half made a weaker case look like the reason.
        //
        // ⚠️ THE LENGTH IS ALREADY DISCOUNTED FOR THE PUSH, so the consumer must not discount it
        // twice: `RoleRhythm.hit` caps `gateFraction` at `1 - push` (on `flowing`, at 0.95). A
        // pushed note therefore still ends inside its own cell when the consumer applies the delay
        // and the gate independently — which is exactly how `TouchInstrumentUIView` does it.
    }

    /// How many cells in `0..<before` the ARP sounds, in this bar. The counterpart of the walk
    /// index: `ArpFigure` advances once per SOUNDED note, so this is what turns a cell index into
    /// a walk position.
    ///
    /// ⚠️ NOT bar-invariant any more, and that difference is worth stating because the walk index
    /// multiplies by it. Under the old Euclidean rule every traverse fired the same count, so
    /// `traverse * firedPerTraverse` was exact. `RoleRhythm` keeps that for five of six
    /// characters; `flowing` with `evolve > 0` fires a different number per bar by design. The
    /// walk then ENTERS the next traverse on a different chord tone than a running total would
    /// give — which is variation on the one character whose whole purpose is to breathe, not an
    /// error. Within a traverse the walk is always consecutive, which is the property the figure
    /// depends on.
    ///
    /// Cost: `limit` calls to a pure function per sounded cell, `limit <= maxPeriodSteps` = 1024.
    /// The driver only calls in when the grid cell changes — a handful of times a second.
    static func arpFiredCount(before limit: Int, bar: Int, rhythm: RoleRhythm.Params,
                              period: Int, seed: UInt64) -> Int {
        var count = 0
        for i in 0..<Swift.max(0, limit)
        where RoleRhythm.hit(bar: bar, cell: i, cellsPerBar: period,
                             params: rhythm, seed: seed) != nil {
            count += 1
        }
        return count
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

    /// Most of a cell a push may eat. Mirrors `RoleRhythm.maxPush` rather than restating it, so
    /// the two cannot drift — a rhythm that can ask for 0.45 and a consumer that honours 0.30
    /// would be a silently truncated groove nobody can see in either file.
    ///
    /// It is a SECOND ceiling and not a duplicate one: `Hit.pushFraction` arrives already clamped,
    /// but `Touch.pushFraction` is a public field on a public struct and this function is `public`
    /// too, so a caller can reach it without ever passing through `RoleRhythm`.
    public static var maxPushFraction: Float { RoleRhythm.maxPush }

    /// How long to hold a generated note-on back so it lands LATE by the rhythm's own amount
    /// (#253 A2b). Seconds, because the consumer already knows its cell length and its clock;
    /// a fraction is what travels between the two.
    ///
    /// Why every one of these cases is a fold to `0` — i.e. "sound it on the grid" — rather than
    /// a `precondition`: this runs inside a performance, on a value a bio mapping may write. A
    /// wrong number must make a note early, never end the take.
    ///
    /// • `nil` — the motion has no timing opinion (all five travelling motions). Today's behaviour
    ///   exactly, and the reason this returns `0` instead of being optional itself: the caller then
    ///   has ONE arithmetic path, and the immediate case is provably unchanged rather than a second
    ///   branch that has to be kept identical by hand.
    /// • Non-finite — NaN and ±infinity both mean "no usable offset". ⚠️ THE `isFinite` CLAUSE BELOW
    ///   IS REDUNDANT FOR NaN AND FOR −∞, and it stays for the one case it alone catches: `+∞`,
    ///   which passes `> 0` and would otherwise reach the `Swift.min` cap (correctly, as it happens
    ///   — but by luck rather than by the guard). Stated because the first version of this bullet
    ///   claimed the opposite, that NaN was caught "by structure instead of by comment, not an
    ///   `isNaN` special case", while the very next line reads `push.isFinite`.
    /// • Negative — "early", which a generated onset cannot be: it is created at its own cell edge,
    ///   with no look-ahead to be early against. Honouring it would need the generator to run a
    ///   cell ahead, which is a different design (and would put the note in the PREVIOUS cell).
    /// • `cellSeconds` not positive — a stopped or corrupt clock. Nothing to be a fraction of.
    public static func pushDelaySeconds(_ pushFraction: Float?, cellSeconds: Double) -> Double {
        guard let push = pushFraction, push.isFinite, push > 0,
              cellSeconds.isFinite, cellSeconds > 0 else { return 0 }
        // Strictly less than one cell BY CONSTRUCTION (`maxPushFraction` is 0.45), which is the
        // property that keeps a pushed note inside its own cell and off the next one's onset.
        return Double(Swift.min(push, maxPushFraction)) * cellSeconds
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
        // Never consulted: `touches` returns through `arpTouches` before this is called, because
        // the arp's x is a degree CELL and not a position on a curve. The value exists only to
        // keep the switch total — 0.5 (the centre, i.e. "no displacement") is the honest one to
        // return if a future caller ever asks, rather than an arbitrary edge.
        case .arp:      return 0.5
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
