//
//  RoleRhythm.swift
//  Echoelmusic — Sequencer
//
//  A RHYTHM PER SOUND ROLE (founder 2026-07-30: *"Alle Soundrubriken von Pads, Bass bis arp etc.
//  brauchen noch verschiedene Rhythmus Regler. Verschiedene variablen die interessante,
//  treibende, hypnotische, dynamische etc. Rhythmus pattern machen"*).
//
//  ⛔ WHY THIS IS A NEW CORE AND NOT A FIELD IN `MoodProfile`, because that is the first thing a
//  reader will want to collapse. `MoodProfile.syncopation` is ONE number for the WHOLE take
//  (`BioComposer.swift`), and the ask is explicitly per role — a driving bass under a hypnotic
//  pad is the entire point. Widening `MoodProfile` per role would mean four copies of a struct
//  whose other FIVE fields (darkness, tension, romance, weird, virtuosity) are genuinely global.
//  (`MoodProfile` has EIGHT fields. An earlier version of this line said "the other three", which
//  undercounted it by five and, worse, hid the three-way collision named in the next paragraph.)
//
//  ⚠️ THREE OF THESE FIVE NUMBERS OVERLAP AN EXISTING GLOBAL DIAL, and A2–A5 will bind both at
//  once, so the precedence is decided HERE rather than discovered per role:
//    · `density`   vs `MoodProfile.liveliness`  — RoleRhythm WINS for the roles it drives.
//    · `push`/`syncopated` vs `MoodProfile.syncopation` — RoleRhythm WINS for those roles.
//    · `accent`    vs `MoodProfile.humanize`    — they COMPOSE: `accent` is the deterministic
//      loud/soft shape, `humanize` stays the random looseness on top of it.
//  The mood dials keep governing everything RoleRhythm does not touch (note CHOICE, register,
//  chord colour) — that is `BioComposer`'s half and this type never reaches into it.
//
//  ⚠️ WHAT "RHYTHM" CAN MEAN HERE, stated plainly because the founder's own earlier decision
//  bounds it: there is NO DRUM KIT and no percussion instrument since #166/#167 ("erstmal gar
//  nicht mehr rein") — `LaneDrumKitVoice` has no instantiation site and `BeatPlayer.attach(to:)`
//  hangs only its preview voice. So a rhythm is made of the melodic roles — WHICH cells sound,
//  HOW HARD, HOW LONG, and HOW FAR OFF the grid — and that is exactly what this type returns. A
//  four-on-the-floor kick is not available and this file must not pretend otherwise.
//  (The one percussive sound the app DOES make is `MetronomeVoice`, live and user-toggleable in
//  the Composition panel. It is a click track, not an instrument — but the earlier absolute
//  "nothing in this app makes a percussive sound" was false, and it is the obvious timing
//  reference a later slice would want to align a groove to.)
//
//  THE SHAPE: six NAMED characters, not another slider. `EchoelValueField` is the law for numeric
//  parameters, and the same law says in as many words that a parameter whose values have NAMES is
//  a `Picker` — "driving" and "hypnotic" are not points on one axis, they differ in which cells
//  fire, where the accent sits and how long the note is held. Six because each is audibly a
//  different rhythm; a menu of twelve subtly different ones is the "more options that sound the
//  same" failure this project has already hit twice (#81, #125).
//
//  Pure Foundation, deterministic from `(bar, cell, params, seed)`, no state and no clock: the
//  caller owns the tick, exactly as `FieldAutoPlay` and `ArpFigure` do. That is what makes a
//  groove assertable in CI — a rhythm is precisely the kind of thing that reads correctly in code
//  and sounds like a stumble on a device.
//
//  ⚠️ NO WRITER AND NO CONSUMER YET (#253 A1). Nothing in `Sources/` calls this: the role
//  bindings are A2 (arp), A3 (bass), A4 (pad), A5 (lead), the bounded timbre/FX trim is A6 and
//  the UI rows are A7. Writing that down is the rule this repo learned twice over — an
//  unreachable core is honest, an unreachable core described as live is what plans get built on.
//  When A2 lands, this paragraph must change with it.
//
//  ⚠️ ONE THING ONLY A DEVICE CAN SETTLE (A6/A7 listening item): `driving` and `dynamic` fire the
//  SAME cells and differ in accent shape and note length (gate ×0.45 vs ×0.7). That is two
//  audible dimensions, which is this file's stated bar — but whether it is enough for the founder
//  to call one of them "treibend" is a hearing question, not a code question. If it is not, the
//  fix is to give `driving` its own selection, and the constraint to respect is that
//  `testDensityNeverLosesNotesAsItRises` must stay provable (a set UNION with the beats is not).
//

import Foundation

public enum RoleRhythm {

    /// The six rhythm characters, in the founder's own vocabulary where it existed.
    ///
    /// ⚠️ THIS NAME SHADOWS `Swift.Character` inside `RoleRhythm`'s scope. Kept because the call
    /// site reads right (`params.character`), it matches the founder's word and the codebase's own
    /// vocabulary (`FXCharacter`, `MoodPreset`) — but anyone adding string handling to THIS type
    /// must write `Swift.Character`, or get a baffling error about a rhythm not being expressible
    /// by a string literal.
    ///
    /// Each one differs in at least TWO of the four dimensions this type controls (selection,
    /// accent, gate, push) — that is the bar for adding one, and the reason there are six rather
    /// than a dozen.
    public enum Character: String, CaseIterable, Sendable, Codable {
        /// Straight, short, hard on the beat. The engine: no push at all, so it reads as machine
        /// time, and a short gate leaves air between the notes for the pulse to be felt.
        case driving
        /// Even spread, long notes, almost no accent — and the pattern ROTATES slowly bar by bar,
        /// which is what makes a repeating figure hypnotic instead of merely repetitive.
        case hypnotic
        /// The loud/soft one: the same cells as `driving` but a contour that moves, so the bar
        /// breathes. This is the character `evolve` changes most.
        case dynamic
        /// Wide. Fewer notes than the density asks for, only on the beats, held long.
        case sparse
        /// Off the beat: the pattern prefers the cells BETWEEN the beats and accents them, with a
        /// small late push — the pull that makes a bassline swing.
        case syncopated
        /// Legato and level: long notes, light accents, a hair behind the grid. How a pad sits
        /// under everything else without competing with it.
        case flowing

        /// Whether `Params.evolve` changes ANYTHING on this character.
        ///
        /// ⛔ THIS EXISTS SO A7 CANNOT SHIP A LYING DIAL (#164, #227). Four of the six ignore
        /// `evolve` entirely — turning it from 0 to 1 on `driving`, `hypnotic`, `sparse` or
        /// `syncopated` produces a bit-identical bar, and a full-range slider that does nothing is
        /// worse than a missing one. The UI row must be hidden or disabled where this is `false`.
        ///
        /// Exhaustive on purpose: adding a seventh character forces a decision here rather than
        /// silently inheriting `false`. And it is asserted against real output rather than trusted
        /// — the test compares `evolve: 0` with `evolve: 1` per character and requires the two to
        /// differ exactly when this says they should.
        ///
        /// (`hypnotic` is the subtle one: it varies bar to bar, but by ROTATION, which is its
        /// character and is a pure function of the bar index. It reads neither `evolve` nor the
        /// seed at any value.)
        public var usesEvolve: Bool {
            switch self {
            case .dynamic, .flowing:                        return true
            case .driving, .hypnotic, .sparse, .syncopated:  return false
            }
        }
    }

    /// Everything a player can set per role.
    ///
    /// Deliberately SMALL. Six characters × five numbers is already a large space; a dial that
    /// does not change what the ear hears is worse than a missing one (#164, #227).
    public struct Params: Equatable, Sendable, Codable {
        /// Which of the six shapes.
        public var character: Character
        /// How much of the grid sounds, 0…1. **0 is silence**, not "a few" — and the converse is
        /// enforced too: any density above 0 fires at least one cell, on every character. Without
        /// that floor `round(density · cells)` silently reached 0 for the bottom 1/32 of the dial,
        /// and `sparse` (which squares the density against a 4-cell grid) stayed silent for its
        /// whole bottom THIRD — a dial that reads "on" and produces nothing.
        public var density: Float
        /// Note length as a fraction of one cell, 0.05…1. Short = staccato, 1 = fills the cell.
        ///
        /// The character SCALES this rather than replacing it, so the dial always does something
        /// in the direction it says — `driving` is short even at gate 1, but gate 1 is still
        /// longer than gate 0.3 on `driving`.
        ///
        /// ⚠️ WITH A KNEE AT THE BOTTOM, which is worth knowing before A7 draws the range: the
        /// product is floored at `minGate`, so on `driving` (×0.45) everything below gate 0.111
        /// lands on the same 0.05, and on `syncopated` (×0.6) everything below 0.083. The dial is
        /// flat there. That is deliberate — a gate of 0 is a click, not a short note — but the
        /// row should not promise resolution it does not have.
        public var gate: Float
        /// How deep the accents cut, 0…1. 0 = every note the same level (a machine), 1 = the
        /// strong cells roughly twice the level of the weak ones.
        ///
        /// ⚠️ HOW MUCH IT CAN CUT IS THE CHARACTER'S CHOICE, not this dial's, and the spread at
        /// `accent == 1` is far from uniform: `dynamic` ≈ 7 dB, `driving` ≈ 5 dB, `syncopated`
        /// ≈ 4.5 dB, `sparse` ≈ 1.5 dB, `hypnotic` ≈ 1 dB, `flowing` ≈ 0.5 dB. The last two are
        /// nearly flat BY DESIGN — an accent is a landmark and those two characters work by not
        /// giving the ear one — so A7 must not present the row as equally effective on all six.
        public var accent: Float
        /// Timing offset in cell fractions, −0.45…0.45. Negative = early, positive = laid back.
        /// The character adds its own on top; the sum is clamped so a note can never cross into
        /// the next cell.
        ///
        /// ⚠️ NaN HERE MEANS "ON THE GRID", not `-0.45`. This is the one dial whose neutral value
        /// is 0 rather than an end of its range, and it is the one a bio mapping is most likely to
        /// feed — so a non-finite value must not read as "maximally early on every note".
        public var push: Float
        /// How much the figure changes from bar to bar, 0…1. **0 is bit-identical bars** — asserted,
        /// because "off" has to mean off rather than "less".
        ///
        /// ⚠️ AND IT ONLY APPLIES TO TWO OF THE SIX CHARACTERS — see `Character.usesEvolve`, which
        /// is the value A7 must read before drawing this row. On `dynamic` it jitters the accent
        /// contour per note; on `flowing` it flips individual cells in and out (a note more or a
        /// note less, which is what breathing sounds like on a pad). On the other four it does
        /// nothing at all, `hypnotic` included: its bar-to-bar rotation IS its character, is a pure
        /// function of the bar index, and consults neither this dial nor the seed.
        public var evolve: Float

        /// Format stamp (#189): the encoder writes it, so a future non-additive migration can
        /// read what it is looking at. Not assigned on decode — two functionally identical
        /// `Params` must not compare unequal because one came off disk.
        public static let currentSchemaVersion = 1
        public private(set) var schemaVersion: Int = Params.currentSchemaVersion

        public init(character: Character = .flowing, density: Float = 0.5, gate: Float = 0.8,
                    accent: Float = 0.4, push: Float = 0, evolve: Float = 0.2) {
            self.character = character
            self.density = density
            self.gate = gate
            self.accent = accent
            self.push = push
            self.evolve = evolve
        }

        /// Additive decode: a `Params` saved before a dial existed loads with that dial's default
        /// instead of the whole setting being thrown away. `character` uses `try?` and not
        /// `decodeIfPresent` for the reason `FieldAutoPlay.Params` states — a raw-value enum whose
        /// stored case a later build removes THROWS `dataCorrupted`, which `decodeIfPresent` does
        /// not absorb.
        ///
        /// And CLAMPED at the boundary, as `FieldAutoPlay.Params.init(from:)` does and for its
        /// stated reason: `hit(...)` clamps at use, so an out-of-range value could not misbehave
        /// musically — but it would sit in memory looking legal and a UI bound straight to
        /// `params.gate` would render `99`.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Params()
            // Enclosing-type statics are written out in full, exactly as
            // `FieldAutoPlay.Params.init(from:)` writes `FieldAutoPlay.maxPeriodSteps`.
            character = (try? c.decode(Character.self, forKey: .character)) ?? d.character
            density = RoleRhythm.clamp01((try? c.decode(Float.self, forKey: .density)) ?? d.density)
            gate = RoleRhythm.clamp01((try? c.decode(Float.self, forKey: .gate)) ?? d.gate)
            accent = RoleRhythm.clamp01((try? c.decode(Float.self, forKey: .accent)) ?? d.accent)
            evolve = RoleRhythm.clamp01((try? c.decode(Float.self, forKey: .evolve)) ?? d.evolve)
            let storedPush = (try? c.decode(Float.self, forKey: .push)) ?? d.push
            push = storedPush.isNaN
                ? 0
                : RoleRhythm.clampRange(storedPush, -RoleRhythm.maxPush, RoleRhythm.maxPush)
        }
    }

    /// What one cell plays. `nil` from `hit(...)` means the cell is silent.
    ///
    /// ⛔ THERE IS NO SUCH THING AS A HIT WITH VELOCITY 0 here, and that is a hard rule rather
    /// than a range check: a note-on at velocity 0 is an inaudible event that still allocates a
    /// voice, still counts against polyphony and still shows up in a log as a played note. This
    /// app has already spent two cycles chasing exactly that ghost (#205's five active notes at
    /// velocity 0, and the eleven missing clamps of #176). Silence is `nil`.
    public struct Hit: Equatable, Sendable {
        /// 0.05…1. Never 0 — see above.
        public var velocity: Float
        /// Note length as a fraction of the cell, 0.05…1.
        public var gateFraction: Float
        /// Timing offset in cell fractions, −0.45…0.45. The consumer turns this into ticks; it
        /// stays a fraction here so this type never needs to know a tempo or a grid.
        public var pushFraction: Float

        public init(velocity: Float, gateFraction: Float, pushFraction: Float) {
            self.velocity = velocity
            self.gateFraction = gateFraction
            self.pushFraction = pushFraction
        }
    }

    /// Most cells a caller may claim one bar has.
    ///
    /// A crash guard of the same family as `FieldAutoPlay.maxPeriodSteps`, not taste: `cellsPerBar`
    /// reaches integer arithmetic (`BreathArp.isActive`'s `cell * active`, and
    /// `Int((density · Float(cells)).rounded())` where `Float(Int.max) == 2^63` is out of `Int`'s
    /// range) and a decoded or hand-edited value near `Int.max` would trap. 256 cells is 1/64
    /// notes across four bars — far past any grid this app offers.
    public static let maxCellsPerBar = 256

    /// Slowest and fastest a note may be, as a fraction of its cell.
    ///
    /// The floor is not cosmetic: a gate of 0 is a note that starts and ends at the same instant,
    /// which every synth voice in this app renders as either a click or nothing at all.
    public static let minGate: Float = 0.05
    public static let maxGate: Float = 1.0

    /// Quietest a hit may be. Its own constant and not a reuse of `minGate` — a velocity floor and
    /// a length floor happen to share a number today and have nothing to do with each other.
    ///
    /// ⚠️ IT CANNOT BIND WITH TODAY'S FORMULA, and saying so is the point: `0.72 ± 0.275` already
    /// lands in `0.445…0.995`, so this is a backstop for a future accent contour, not a live
    /// clamp. A guard described as load-bearing when it is not is how the next slice removes the
    /// one that is.
    public static let minVelocity: Float = 0.05

    /// The furthest a note may sit from its grid cell. Below half a cell by construction — at
    /// exactly 0.5 a "late" note and the next cell's "early" note would land on the same instant
    /// and the ear would hear a flam, which is the defect `TouchQuantizer`'s tolerance exists to
    /// prevent.
    public static let maxPush: Float = 0.45

    // MARK: - The one entry point

    /// What the role plays at `cell` of `bar`, or `nil` for silence.
    ///
    /// The ONLY public entry point, and the helpers below are `private` so that stays true: the
    /// `cellsPerBar` clamp that keeps `BreathArp.isActive` from trapping lives here, so a caller
    /// reaching past this function for `fires`/`spread` would reach past the crash guard too.
    ///
    /// - Parameters:
    ///   - bar: bar index from the caller's clock. May be negative; folded, not rejected.
    ///   - cell: cell index within the bar. Folded into `0..<cellsPerBar`, so a caller counting
    ///     absolute cells may hand over anything.
    ///   - cellsPerBar: the grid. Clamped to `1...maxCellsPerBar`.
    ///   - params: the dials.
    ///   - seed: makes `evolve` reproducible on the two characters that use it. Where
    ///     `Character.usesEvolve` is false, or at `evolve == 0`, the result does not depend on it
    ///     at all — which is asserted rather than assumed.
    public static func hit(bar: Int, cell: Int, cellsPerBar: Int,
                           params: Params, seed: UInt64) -> Hit? {
        let cells = Swift.min(maxCellsPerBar, Swift.max(1, cellsPerBar))
        let position = floorMod(cell, cells)
        let density = clamp01(params.density)
        guard density > 0 else { return nil }

        let evolve = clamp01(params.evolve)
        // One draw stream per (role seed, bar, CELL). The cell belongs in the fold and leaving it
        // out was a real bug, not a shortcut: every cell of a bar then re-derived the identical
        // stream and got the identical first draw, so `flowing`'s "flip this cell" became one coin
        // toss that inverted the WHOLE bar — at density 1 that is a silent bar roughly every fifth
        // one. Per-cell is also what the two characters' own comments describe.
        //
        // Re-derived from the indices rather than carried in state for the reason
        // `FieldAutoPlay.travel` gives about its walk: this is a pure function, so a caller may ask
        // for any cell of any bar in any order — a scrub, a test, a re-render — and must get the
        // same answer.
        var rng = SeededRNG(seed: seed
                            &+ UInt64(bitPattern: Int64(bar)) &* 0x9E3779B97F4A7C15
                            &+ UInt64(bitPattern: Int64(position)) &* 0xD1342543DE82EF95
                            &+ 0x524F4C45_00000000)                       // "ROLE"

        guard fires(position: position, cells: cells, density: density,
                    character: params.character, bar: bar,
                    evolve: evolve, rng: &rng) else { return nil }

        let strength = accentStrength(position: position, cells: cells,
                                      character: params.character,
                                      evolve: evolve, rng: &rng)
        // Base level sits under 1 so an accent has somewhere to go, and the accent DEPTH decides
        // how far apart loud and soft end up. At accent 0 every hit is 0.72 — a machine, which is
        // a legitimate musical choice and not a bug.
        let depth = clamp01(params.accent)
        let velocity = clampRange(0.72 + depth * (strength - 0.5) * 0.55, minVelocity, 1)

        // PUSH IS COMPUTED FIRST, because the gate's ceiling depends on it. A note that starts
        // 0.05 late and then fills its whole cell ends 5 % into the next one — which `gateScale`'s
        // own comment promised could not happen, and which `flowing` (scale 1.0 AND an
        // unconditional +0.05) did on every single note. Tying across cells is a voice-stealing
        // decision that belongs to the consumer, not to a rhythm generator, so the length yields.
        let requested = params.push.isNaN ? 0 : params.push
        let push = clampRange(clampRange(requested, -maxPush, maxPush)
                              + pushBias(params.character, position: position, cells: cells),
                              -maxPush, maxPush)
        // `Swift.max(minGate, …)` only matters if `maxPush` ever rises past `1 - minGate`; today
        // the headroom is at least 0.55. It is here so the range can never invert.
        let headroom = Swift.max(minGate, 1 - Swift.max(0, push))
        let gate = clampRange(clamp01(params.gate) * gateScale(params.character),
                              minGate, Swift.min(maxGate, headroom))

        return Hit(velocity: velocity, gateFraction: gate, pushFraction: push)
    }

    // MARK: - Selection: which cells sound

    /// Whether this cell is one of the ones that sound.
    ///
    /// Built on the SAME even-spread rule the rest of this repo uses
    /// (`BreathArp.isActive`, reused by `FieldAutoPlay.fires`): an even distribution is heard as
    /// a RATE, where a probability roll at the same average is heard as stumbling. Each character
    /// then transforms that base set — which is what makes them different rhythms rather than
    /// different amounts of one rhythm.
    private static func fires(position: Int, cells: Int, density: Float, character: Character,
                              bar: Int, evolve: Float, rng: inout SeededRNG) -> Bool {
        let beat = Swift.max(1, cells / 4)

        switch character {
        case .driving, .dynamic:
            // THE SAME CELLS, deliberately, and the shared case says so rather than two branches
            // that look different and are not. `driving` used to force `position == 0` on top —
            // dead code, because `spread` floors the active count at 1 whenever the density is
            // above 0 and `isActive(0, active, cells)` reduces to `0 < active`, i.e. the downbeat
            // is ALWAYS in the set. These two characters are told apart by their accent shape and
            // their note length (×0.45 vs ×0.7); see the device-listening note in the header.
            return spread(position, cells: cells, density: density)

        case .hypnotic:
            // ROTATION is the whole character: the same figure, entering at a different cell each
            // bar, so it never settles into "the same loop" for the ear. One cell per bar, so it
            // takes a full cycle to come back — slow enough to be felt rather than heard as a
            // change.
            //
            // `&-` and not `-`: `bar` is an unbounded `Int` from the caller's clock, and
            // `0 - Int.min` TRAPS. A wrap merely picks a different rotation of the same figure,
            // which is inaudible nonsense at bar ±9·10^18 and cannot crash a performance. (Found
            // by the absurd-bar test, not by reading — the plain `-` looked obviously fine.)
            return spread(floorMod(position &- bar, cells), cells: cells, density: density)

        case .sparse:
            // Only on the beats, and fewer of them: `density` is squared, which makes the
            // low half of the dial genuinely wide rather than merely thinner. The floor inside
            // `spread` is what keeps the squared value from rounding to zero notes — it used to
            // silence the whole bottom third of this character's dial.
            guard position % beat == 0 else { return false }
            return spread(position / beat, cells: Swift.max(1, cells / beat),
                          density: density * density)

        case .syncopated:
            // Prefer the cells BETWEEN the beats. The downbeat only sounds when the density is
            // high enough that leaving it out would read as a mistake rather than as a push.
            if position % beat == 0 { return density > 0.85 }
            return spread(floorMod(position - beat / 2, cells), cells: cells, density: density)

        case .flowing:
            let base = spread(position, cells: cells, density: density)
            // The one place `evolve` changes the SELECTION rather than the level: a flowing part
            // is where an extra or a missing note reads as breathing rather than as an error.
            // PER CELL — the draw stream is folded from the cell index, so this is a note more or
            // a note less and never a polarity flip of the whole bar.
            guard evolve > 0 else { return base }
            return rng.unit() < evolve * 0.18 ? !base : base
        }
    }

    /// The even-spread rule, with the active count derived exactly as everywhere else in this
    /// repo so the three call sites cannot drift apart — plus ONE floor this repo's other two
    /// sites do not have.
    ///
    /// ⚠️ THE FLOOR IS THE POINT: `round(density · cells)` reaches 0 for every density below
    /// `1/(2·cells)`, and `sparse` feeds it a SQUARED density against a quarter-size grid, so it
    /// reached 0 for everything under ~0.354. `Params.density` promises that only 0 is silence, so
    /// any density above 0 fires at least one cell. Monotonicity survives because `max(1, ·)` of a
    /// monotone function is monotone.
    private static func spread(_ position: Int, cells: Int, density: Float) -> Bool {
        let d = clamp01(density)
        guard d > 0 else { return false }
        let active = Swift.max(1, Int((d * Float(Swift.max(1, cells))).rounded()))
        guard active < cells else { return true }
        return BreathArp.isActive(floorMod(position, cells), active: active, steps: cells)
    }

    // MARK: - Accent: how hard

    /// 0…1, where 0.5 is "neither accented nor ducked". The velocity maths above turns this into
    /// a level, so a character that returns a constant 0.5 sounds perfectly flat whatever the
    /// accent dial says — which is what `flowing` very nearly does, and `hypnotic` nearly too.
    /// `Params.accent` lists the resulting spread per character; those numbers and these returns
    /// must be changed together.
    private static func accentStrength(position: Int, cells: Int, character: Character,
                                       evolve: Float, rng: inout SeededRNG) -> Float {
        let beat = Swift.max(1, cells / 4)
        let onDownbeat = position == 0
        let onBeat = position % beat == 0

        switch character {
        case .driving:
            return onDownbeat ? 1 : (onBeat ? 0.8 : 0.35)
        case .hypnotic:
            // Barely there on purpose: an accent is a landmark, and a hypnotic figure works by
            // not giving the ear one.
            return onDownbeat ? 0.62 : 0.46
        case .dynamic:
            // A contour, plus the only per-note level jitter in this type. `evolve` 0 keeps the
            // contour exactly — the jitter is added, never substituted.
            let wave = 0.5 + 0.42 * sinf(2 * Float.pi * Float(position) / Float(Swift.max(1, cells)))
            let jitter = evolve > 0 ? (rng.unit() - 0.5) * evolve * 0.3 : 0
            return clamp01(wave + jitter)
        case .sparse:
            return onDownbeat ? 0.95 : 0.7
        case .syncopated:
            // The mirror of driving: the OFF-beats are the loud ones. That inversion is the
            // character, far more than the placement is.
            return onBeat ? 0.3 : 0.85
        case .flowing:
            return onDownbeat ? 0.56 : 0.48
        }
    }

    // MARK: - Gate and push

    /// How the character scales the player's gate. Never 0 and never above 1; whether the RESULT
    /// spills into the next cell is decided in `hit`, which gives the length back the room the
    /// push takes — this function knows nothing about timing.
    ///
    /// `hypnotic` is 0.9 and not 1.0 on purpose, and it is the second dimension that keeps it
    /// apart from `flowing`: a repeating figure needs a hair of air so consecutive notes retrigger
    /// audibly, where a pad wants to fill the cell and be legato. Without it the two characters
    /// collapsed onto each other at `accent == 0` (same cells at bar 0, same level, same length)
    /// with nothing left but 0.05 of push — inaudible, which is exactly the #81/#125 failure.
    private static func gateScale(_ character: Character) -> Float {
        switch character {
        case .driving:    return 0.45
        case .hypnotic:   return 0.9
        case .dynamic:    return 0.7
        case .sparse:     return 1.0
        case .syncopated: return 0.6
        case .flowing:    return 1.0
        }
    }

    /// The character's own timing offset, added to the player's `push`.
    ///
    /// Only two characters have one, and both for a named reason: `syncopated` sits late on its
    /// off-beats (the pull that makes a bassline swing) and `flowing` sits a hair behind
    /// everywhere (laid back). `driving` is deliberately DEAD straight — that is the point of it,
    /// and giving every character a little push would erase the difference.
    private static func pushBias(_ character: Character, position: Int, cells: Int) -> Float {
        let beat = Swift.max(1, cells / 4)
        switch character {
        case .syncopated: return position % beat == 0 ? 0 : 0.12
        case .flowing:    return 0.05
        case .driving, .hypnotic, .dynamic, .sparse: return 0
        }
    }

    // MARK: - Pure pieces

    /// Flooring modulo: always in `0..<m`, including for negative `a`. Swift's `%` truncates
    /// toward zero, so `-1 % 4 == -1` — used as an index that is a crash, and "fixed" with `abs`
    /// it is a silently mirrored pattern.
    static func floorMod(_ a: Int, _ m: Int) -> Int {
        guard m > 0 else { return 0 }
        let r = a % m                  // safe for Int.min: |r| < m, no overflow
        return r < 0 ? r + m : r
    }

    /// NaN-safe by argument order: `Swift.max(0, x)` returns 0 for NaN, `Swift.max(x, 0)` returns
    /// NaN. This app has shipped permanent silence from getting that backwards (CLAUDE.md).
    static func clamp01(_ v: Float) -> Float {
        Swift.min(1, Swift.max(0, v))
    }

    /// The same NaN-safety for an arbitrary range, and by the same mechanism rather than by an
    /// `isFinite` branch.
    ///
    /// ⛔ THE `isFinite` VERSION WAS WRONG AND THIS IS WHY IT IS GONE: substituting `lower` for
    /// every non-finite input sent `+infinity` to the BOTTOM of the range. `Swift.max`/`Swift.min`
    /// already do the right thing on all three cases, because both are written as
    /// `y >= x ? y : x` / `y < x ? y : x` and NaN fails every comparison:
    ///   · `+inf` → `upper`   · `-inf` → `lower`   · `NaN` → `lower`
    /// A caller whose neutral value is not `lower` — `push`, whose neutral is 0 — must therefore
    /// map NaN itself before calling, and `hit` does.
    static func clampRange(_ v: Float, _ lower: Float, _ upper: Float) -> Float {
        Swift.min(upper, Swift.max(lower, v))
    }
}
