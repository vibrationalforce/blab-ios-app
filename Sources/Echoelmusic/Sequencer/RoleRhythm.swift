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
//  ⚠️ THREE OF THESE FIVE NUMBERS OVERLAP AN EXISTING GLOBAL DIAL, and A2–A4 bind both at
//  once, so the precedence is decided HERE rather than discovered per role:
//  (It said "A2–A5" until 2026-07-30. A5 was rejected — see the paragraph 60 lines down — and this
//  is the block a session reads BEFORE wiring a new role, so a stale range here would have sent one
//  looking for a lead binding that will never exist.)
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
//  ✅ THREE CONSUMERS AND THREE WRITERS, ALL REACHABLE.
//    · ARP (#253 A2/A7) — the Field's `.arp` motion asks this type which cells sound, how hard and
//      how long (`FieldAutoPlay.arpTouches` → `Params.arpRhythm`); the sound reaches the ear through
//      `TouchInstrumentUIView.autoPlayTick`. A PLAYER sets four dials from the Field panel's
//      Rhythm / Note length / Accent / Evolve rows (`EchoelStudioView.fieldArpRhythmFields` →
//      `StudioDefaultKeys.fieldArpRhythm*` → `FloatingVisualWindow.fieldAutoPlay`).
//    · BASS (#253 A3) — `BioComposer.appendBass` asks how the WALKING bass is SHAPED: which steps
//      it lands on for two of the six characters, and how hard and how long for all of them
//      (`Input.bassRhythm`, `nil` = the genre's own grid); the Mood panel's Bass rhythm Picker
//      writes `StudioDefaultKeys.bassRhythm`. That consumer passes `character` + `density` + all
//      THREE remaining dials EXPLICITLY (`gate: 0.8, accent: 0.4, evolve: 0.2`, written out at its
//      own call site) — so the "editing a default re-voices" warning further down covers the ARP
//      ONLY. The bass does not follow this file's defaults, deliberately: they arrive from the
//      arp's feel, and a re-tune there must not silently re-voice every bassline.
//      (This bullet said the opposite for one commit, in the same commit that made it explicit.)
//
//  `push` still has no reader on EITHER consumer, and that is the one number this type promises and
//  nothing honours: `arpTouches` drops it (A2b owns giving the generated onset its own scheduled
//  delay) and `BioComposer.Note.startStep` is a whole 16th, which cannot express 0.12 of a cell at
//  all. So `syncopated`'s late pull and `flowing`'s laid-back hair are computed, carried, and thrown
//  away by both. No UI copy may promise them until A2b lands — the A7 review already had to strike
//  exactly that promise out of two blurbs.
//    · PAD (#253 A4) — `BioComposer.roleRhythmOnsets`, called from `composeHarmonic`, decides when
//      the CHORD re-articulates on every non-arpeggiated pad path and when an arp's notes land
//      (never their pitch order); the Mood panel's Pad rhythm Picker writes
//      `StudioDefaultKeys.padRhythm`. Like the bass it passes gate/accent/evolve explicitly.
//      It does NOT govern the inner pulse layer, which keeps its own fixed grid.
//
//  `density` has no arp writer for its own stated reason (the Field's Density row is the one rate
//  control and `arpTouches` overwrites the stored copy with it).
//
//  ⛔ A5 (LEAD) IS REJECTED, NOT PENDING — and this is the paragraph that stops it being re-planned
//  every few sessions. **There is no lead melody in this product.** Every curated genre carries
//  `HarmonicProfile.leadDensity == 0`, nothing mutates it, and `dubMelody` / `trapMelody` /
//  `ambientMelody` have no caller — so `composeHarmonic`'s melody block (~120 lines,
//  `BioComposer.swift` 2258–2380; an earlier version of this line said ~170) never runs and no
//  `.lead`-role note is ever composed. Note that of the three callerless melody functions, only
//  `trapMelody` and `ambientMelody` emit `.lead` at all — `dubMelody` emits harmony and bass. All
//  three are unreachable, which is the load-bearing half for all of them.
//  The absence is a FOUNDER DECISION (2026-07-09: "die Melodie
//  in den Genres war zu laut und zu unnatürlich … besser wenn die komplett weg sind"), not a gap to
//  fill. A5 was fully BUILT on 2026-07-30 — Input field, `roleRhythmOnsets` binding, gate-driven
//  note lengths, accent-scaled velocity, a Mood-panel Picker — and then reverted in the same cycle,
//  because a Picker that does nothing on every genre is the #135/#164/#227 lying-control defect.
//  ⚠️ **THAT CODE IS GONE — not archived, not stashed, not in any commit.** The revert was a
//  `git checkout --`, verified unrecoverable down to `git fsck --lost-found`. (This paragraph said
//  "the diff is in that commit's body" for one commit, which was false and would have sent the next
//  session hunting for prose — the exact failure this header spends four paragraphs warning about.)
//  The DESIGN survives as a re-implementation spec in
//  `scratchpads/PLAN_LEAD_RHYTHM_A5_2026-07-30.md` — ~60 lines, both non-obvious traps recorded.
//  `LeadRoleAbsenceTests` (BLOCKING bundle) fails the moment a genre sings again, and names the FIVE
//  dormant paths that wake with it.
//  ⚠️ Do NOT read this as "the lead code is dead, delete it". `tameLeadPitch` and
//  `IntroAttenuation.leadFactor` hold real founder tuning from 2026-07-07/07-11, and #196 is an open
//  task on the lead's output gain. Dormant-and-documented, not deleted — that call is the founder's.
//
//  ✅ A6 IS SHIPPED — the bounded timbre trim, at the bottom of this file (`TimbreTrim` +
//  `timbreTrim(for:)`). As predicted it is NOT a fourth consumer of `hit`: it never asks which cells
//  sound, it reads the CHARACTER and nudges a patch, so the consumer list above stays at three.
//  Its ONE reader is `EchoelStudioView.applyTakeSound`, which trims a LOCAL COPY of `currentPatch`
//  at push time and is reached from all three places the take voice gets a patch (the Sound panel,
//  `generate()` and the open-project path — they were three duplicated `synth.apply` pairs and are
//  now one helper). The WRITER is the Mood panel's existing **Pad rhythm** Picker: no new control,
//  because the founder asked for the tone to follow the rhythm, not for a tone dial.
//  Neutral when no character is chosen (`padRhythm == ""`), so a player who never opened that row
//  hears the genre's patch bit-identically.
//  Two non-role items remain open: **A2b** (make `push` actually late — see the paragraph above)
//  and the **inner pulse layer**, which no character governs (`Input.padRhythm`'s doc states that
//  deliberately). The Field/touch voice is deliberately NOT trimmed — it has its own character
//  (`fieldArpCharacter`) and belongs to a Field slice (#222/#224).
//  (This block said "TWO consumers … A4 (pad) has no writer" for one commit — written in the commit
//  that added the pad as the third. Twenty lines above, this same header spends a paragraph on
//  exactly that failure with A2. Update it IN the diff that adds a consumer, not after.)
//
//  ⚠️ THE DEFAULT IS STILL LOAD-BEARING even now that a UI exists, because `StudioDefaultKeys`
//  mirrors it: editing `Params`' default re-voices the arp for every user who has not touched a row.
//  `TouchSurfaceStorageKeysTests` compares the two against each other for exactly that reason.
//  (The first version of this paragraph said "NO WRITER AND NO CONSUMER YET" and asked to be
//  updated when A2 landed. A2 landed in `06a43c2` and it was not — which would have told the next
//  session this type is unreachable and invited either a duplicate binding or a deletion. That is
//  the failure this repo keeps paying for, and it is why this note names its writer rather than
//  promising to.)
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
        /// Even spread, long notes, almost no accent — and the pattern ROTATES slowly, one cell per
        /// `bar` index, which is what makes a repeating figure hypnotic instead of merely repetitive.
        ///
        /// ⚠️ "PER BAR" IS THE CALLER'S WORD, not a musical promise this type can keep. The arp
        /// advances `bar:` per traverse; `BioComposer` has only a single 16-step looping bar, so it
        /// advances the index per CHORD SECTION instead (`appendBass`) — the figure enters at a
        /// different cell of each section and then repeats with the loop. Both are legitimate
        /// readings of "rotation", but a reader of this line must not conclude the bass never
        /// settles: a one-bar loop always does.
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

        /// Whether `Params.accent` can only ever make a SMALL difference on this character.
        ///
        /// ⛔ SAME PURPOSE AS `usesEvolve`, and it exists because the first version of the A7 UI
        /// hard-coded `character == .hypnotic || character == .flowing` in the view — twenty lines
        /// under a comment congratulating itself for reading `usesEvolve` off the engine instead of
        /// duplicating it. That list was also WRONG: `sparse` spreads ≈ 1.3 dB at `accent == 1`,
        /// MORE than `hypnotic`'s ≈ 1.0 dB, and it was the one left out. So on Sparse the Accent row
        /// swept its whole range with nothing audible and nothing on screen explaining why.
        ///
        /// The split is not a judgement call — there is a 2.6× gap in the measured spreads
        /// (`dynamic` 5.8 dB · `driving` 3.9 · `syncopated` 3.5 ‖ `sparse` 1.3 · `hypnotic` 1.0 ·
        /// `flowing` 0.5). `RoleRhythmTests` derives the same split from real `hit(...)` velocities
        /// and requires it to match this switch, so re-tuning `accentStrength` without revisiting
        /// this flag turns red instead of silently mislabelling a row.
        public var accentIsSubtle: Bool {
            switch self {
            case .sparse, .hypnotic, .flowing:      return true
            case .driving, .dynamic, .syncopated:   return false
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
        /// `accent == 1` is far from uniform: `dynamic` ≈ 5.8 dB, `driving` ≈ 3.9 dB, `syncopated`
        /// ≈ 3.5 dB, `sparse` ≈ 1.3 dB, `hypnotic` ≈ 1.0 dB, `flowing` ≈ 0.5 dB. Three of them are
        /// nearly flat BY DESIGN — an accent is a landmark and those characters work by not giving
        /// the ear one — which is why `Character.accentIsSubtle` exists rather than a list in a view.
        ///
        /// ⚠️ THESE SIX NUMBERS WERE OVERSTATED IN THE FIRST VERSION (7 / 5 / 4.5 / 1.5 / 1 / 0.5),
        /// and the top three were the wrong ones to get wrong: they are what a caption promising a
        /// "strong accent" is measured against. `velocity = 0.72 + accent · (strength − 0.5) · 0.55`,
        /// so at `accent == 1` the loudest and quietest cells of a bar are e.g. 0.951 / 0.489 for
        /// `dynamic` — a ratio of 1.945, i.e. 5.8 dB, not 7. Corrected by measurement, and
        /// `RoleRhythmTests` now derives the subtle/strong split from real `hit(...)` output so this
        /// table cannot drift away from the code again.
        ///
        /// ⚠️ AND IT GATES `evolve` ON `dynamic`: that character's evolve is a jitter ADDED TO
        /// `strength`, so the `accent ·` factor annihilates it at `accent == 0` — a bar is then
        /// bit-identical at evolve 0 and evolve 1. `flowing` is unaffected (its evolve flips which
        /// cells sound, upstream of this multiply). A UI offering both dials must say so.
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
    /// range) and a decoded or hand-edited value near `Int.max` would trap.
    ///
    /// ⚠️ IT DELIBERATELY EQUALS `FieldAutoPlay.maxPeriodSteps`, and that is the whole reason it is
    /// 1024 rather than the 256 it shipped with in A1. `FieldAutoPlay.arpTouches` passes its
    /// already-clamped `periodSteps` straight in as `cellsPerBar`, so a LOWER cap here would fold
    /// it silently: at a traverse of 512 the rhythm would repeat twice inside one traverse and the
    /// "beat" would be 64 rather than 128, making that file's "one traverse = one bar" and
    /// "beat = periodSteps / 4" both false without a single test noticing. Two caps for one
    /// quantity in two files is precisely the drift both files warn about. Widening is safe: at
    /// 1024 cells `isActive`'s `cell * active` peaks near 10^6.
    ///
    /// A test asserts the two constants are equal so a future edit to either one fails loudly.
    public static let maxCellsPerBar = 1024

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

    /// The level of a hit with no accent at all — what `Hit.velocity` returns on every cell at
    /// `accent == 0`.
    ///
    /// It is the base term of the velocity formula in `hit(...)` and is READ there rather than
    /// repeated as a literal — the first version of this constant left the `0.72` in the formula and
    /// only documented that the two must be changed together, which is the same duplication one file
    /// further in.
    ///
    /// ⛔ IT IS PUBLIC BECAUSE A CONSUMER HAS TO DIVIDE BY IT. `Hit.velocity` is an ABSOLUTE level
    /// around this neutral, but `BioComposer` already owns the bass's level (the genre's mix balance
    /// times the body's energy) and only wants the accent SHAPE — so it multiplies its own velocity
    /// by `beat.velocity / neutralVelocity`. That divisor was a bare `0.72` literal in `BioComposer`
    /// for one commit, i.e. a private formula of this file copied into another file with no way for a
    /// re-tune here to reach it: raising the base level would have silently made every bassline
    /// quieter. `RoleRhythmTests` asserts an unaccented hit comes back at exactly this value, in the
    /// BLOCKING bundle, so the two can no longer drift apart in silence either.
    public static let neutralVelocity: Float = 0.72

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
        let velocity = clampRange(neutralVelocity + depth * (strength - 0.5) * 0.55,
                                  minVelocity, 1)

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
            // ROTATION is the whole character: the same figure, entering at a different cell for
            // each `bar` index, so it does not sit still. One cell per index, so it takes a full
            // cycle to come back — slow enough to be felt rather than heard as a change.
            //
            // ⚠️ WHAT `bar` MEANS IS THE CALLER'S CHOICE and it decides whether this is audible at
            // all. `BioComposer` advances it per chord section of a single looping bar, and a caller
            // whose sections are 5 steps long must be careful: at `cells == 16` only `bar % 4`
            // matters, so passing the plain section INDEX there cancels exactly against the
            // section's own start cell (5·idx ≡ idx mod 4) and every section fires on its own
            // downbeat — i.e. the caller's default grid, which is the one place an override must not
            // land. `appendBass` therefore measures the rotation from the section's own downbeat.
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

// MARK: - A6: the bounded timbre trim

public extension RoleRhythm {

    /// A SMALL, bounded nudge to a sound's timbre, derived from the rhythm character that is
    /// playing it (#253 A6, founder 2026-07-30: *"Die Sound Charakter werden dadurch auch minimal
    /// beeinflusst für mehr organisches Sound Design"*).
    ///
    /// WHY THIS EXISTS AT ALL. A real player does not keep one timbre and change only the
    /// rhythm — a short, hard, on-the-beat figure is played with a brighter, snappier sound than
    /// a long legato one, and that agreement between groove and tone is most of what "organic"
    /// means. This type is that agreement, and nothing more.
    ///
    /// ⛔ "MINIMAL" IS THE WHOLE SPECIFICATION, not a hedge. The two most expensive bugs this
    /// project has had are #81 and #125 — every genre converging on one sound. A trim that pulled
    /// each genre toward a per-character target would reintroduce exactly that, six targets
    /// instead of one. So the numbers below are deliberately tiny (≤ 0.05 on a 0…1 brightness,
    /// ≤ ±12 % on cutoff, ≤ ±22 % on a time) and they are RELATIVE to whatever patch arrives:
    /// two genres a semitone apart in brightness stay a semitone apart after the trim.
    /// `GenreFamilyDistinctnessTests`' premise is untouched by construction, and
    /// `RoleTimbreTrimTests` asserts the bound rather than trusting this paragraph.
    ///
    /// ⚠️ THE DIRECTION IS NOT FREE — it follows the character's own gate and accent, so the
    /// trim can never contradict the rhythm it came from:
    ///   · `driving` / `dynamic` / `syncopated` — short gates, strong accents → BRIGHTER, more
    ///     open filter, faster attack, shorter release. The note has to speak and then get out
    ///     of the way.
    ///   · `hypnotic` / `sparse` / `flowing` — long gates, subtle accents → DARKER, softer
    ///     filter, slower attack, longer release. These characters work by blurring into
    ///     themselves.
    /// That split is exactly `Character.accentIsSubtle`, and the test derives it from this table
    /// rather than restating it — so re-tuning one without the other turns red.
    ///
    /// ⛔ NOT IDEMPOTENT, AND THAT IS WHY IT MUST NEVER BE STORED. `trimmed(_:)` MULTIPLIES, so
    /// feeding its own output back in compounds (0.88² = 0.77, well outside the stated bound).
    /// The one caller therefore applies it to a LOCAL COPY at the moment the patch is pushed to
    /// the voice (`EchoelStudioView.applyTakeSound`) and never writes it back into
    /// `currentPatch` — which also keeps every number in the Sound panel honest: the player sees
    /// the patch they chose, not the patch plus an invisible offset. If a later slice ever wants
    /// to persist a trimmed patch, it must trim the BASE once, not the current value.
    struct TimbreTrim: Equatable, Sendable {
        /// Added to `brightness` (0…1), then clamped.
        public var brightness: Float
        /// Multiplies `filterCutoff`, then clamped to the live Sound panel's own 20…18000 Hz.
        public var cutoffFactor: Float
        /// Multiplies `attack`, then floored at the click-safe 3 ms onset the articulation macro
        /// already respects — a faster attack must not become a knack.
        public var attackFactor: Float
        /// Multiplies `release`, then floored at 50 ms.
        public var releaseFactor: Float

        /// The widest any field may move, asserted in CI. Written here rather than in the test so
        /// the bound lives with the numbers it bounds.
        public static let maxBrightnessShift: Float = 0.05
        public static let maxCutoffFactorDeviation: Float = 0.12
        public static let maxTimeFactorDeviation: Float = 0.22

        /// The identity — every field neutral. This is what "no character chosen" resolves to,
        /// and `trimmed(_:)` with it returns its input unchanged (asserted).
        public static let neutral = TimbreTrim(brightness: 0, cutoffFactor: 1,
                                              attackFactor: 1, releaseFactor: 1)

        public init(brightness: Float, cutoffFactor: Float,
                    attackFactor: Float, releaseFactor: Float) {
            self.brightness = brightness
            self.cutoffFactor = cutoffFactor
            self.attackFactor = attackFactor
            self.releaseFactor = releaseFactor
        }

        /// The patch as this character would voice it. Pure: the input is untouched.
        ///
        /// Every write is clamped, and each clamp is `Swift.min(upper, Swift.max(lower, v))`
        /// rather than an `isFinite` branch — a non-finite value in a decoded patch must land on
        /// a legal number, not propagate (CLAUDE.md's NaN-argument-order law, and the same
        /// mechanism `clampRange` above already uses).
        public func trimmed(_ patch: SynthPatch) -> SynthPatch {
            var p = patch
            p.brightness   = RoleRhythm.clamp01(patch.brightness + brightness)
            p.filterCutoff = RoleRhythm.clampRange(patch.filterCutoff * cutoffFactor, 20, 18_000)
            p.attack       = RoleRhythm.clampRange(patch.attack * attackFactor, 0.003, 10)
            p.release      = RoleRhythm.clampRange(patch.release * releaseFactor, 0.05, 20)
            return p
        }
    }

    /// The trim for one character. Exhaustive on purpose: a seventh character forces a decision
    /// here instead of silently inheriting a neutral trim and shipping a rhythm whose tone does
    /// not follow it.
    static func timbreTrim(for character: Character) -> TimbreTrim {
        switch character {
        // Speaks and gets out of the way. The brightest and snappiest of the six, because it is
        // the only one with no push at all — machine time needs a transient to read as such.
        case .driving:
            return TimbreTrim(brightness: 0.05, cutoffFactor: 1.12,
                              attackFactor: 0.88, releaseFactor: 0.88)
        // Same cells as driving, moving contour. Less extra brightness precisely BECAUSE its
        // accent already carries the movement (≈ 5.8 dB, the roster's widest) — doubling the
        // emphasis in the timbre would make the loud notes shrill rather than louder.
        case .dynamic:
            return TimbreTrim(brightness: 0.03, cutoffFactor: 1.06,
                              attackFactor: 0.90, releaseFactor: 0.94)
        // Off the beat, and the shortest release of the six: an offbeat that rings into the next
        // beat stops reading as offbeat at all.
        case .syncopated:
            return TimbreTrim(brightness: 0.04, cutoffFactor: 1.09,
                              attackFactor: 0.90, releaseFactor: 0.85)
        // Rotating figure, long notes, almost no accent. Darker and slower so the repetition
        // blurs into itself — that blur IS what makes a repeating figure hypnotic.
        case .hypnotic:
            return TimbreTrim(brightness: -0.04, cutoffFactor: 0.93,
                              attackFactor: 1.10, releaseFactor: 1.16)
        // Few notes, held long. Gets the LONGEST release of the six: with fewer onsets the tail
        // is what fills the bar, and this is the character whose whole point is space.
        case .sparse:
            return TimbreTrim(brightness: -0.03, cutoffFactor: 0.95,
                              attackFactor: 1.06, releaseFactor: 1.22)
        // Legato, level, a hair late. The darkest and slowest — this is how a pad sits UNDER
        // everything else instead of competing with it, which is the character's own doc.
        case .flowing:
            return TimbreTrim(brightness: -0.05, cutoffFactor: 0.90,
                              attackFactor: 1.18, releaseFactor: 1.14)
        }
    }
}
