// TouchQuantizer.swift
// Echoel — ULTRASYNC: the touch instrument in time (founder 2026-07-28, "damit das Touch
// Instrument immer perfekt im timing ist auch microtime — somit wird ungeschicktes Spielen
// auch zum ästhetischen Ereignis; sei hier ruhig etwas creativer mit delays etc.").
//
// WHAT WAS MISSING, precisely. `TouchInstrumentView` already quantizes PITCH into the take's
// MusicalKey — playing a wrong note is impossible by construction. It does not quantize
// TIME: touches go straight to `PolySynthVoice.noteOn`. So a clumsy touch is a right note at
// a wrong moment, which is exactly what playing badly feels like.
//
// THE PHYSICAL LAW THIS TYPE IS BUILT AROUND. A live note cannot be moved earlier. Once the
// finger has landed you may hold the note back; you cannot un-play it. Every DAW quantizer
// rounds to the NEAREST grid point, and half of those roundings move a note backwards —
// which is fine for a recorded take being edited afterwards and impossible for an instrument
// being played now. So this rounds asymmetrically:
//
//   · closer to the NEXT grid point (early)  → DELAY onto it. Causally free: wait.
//   · closer to the PREVIOUS one   (late)    → let it SOUND where it landed, and restore the
//                                              pulse with an ECHO on the next grid point.
//
// The echo is the "creative with delays" half, and it is why a late touch becomes musical
// rather than merely corrected: the mistake is not erased, it is answered on the beat.
//
// MICROTIMING is the other half of the ask. Hard-quantized playing is machine-stiff, so the
// result carries a seeded per-note offset — reusing `Humanizer`, which is already tested,
// rather than growing a second jitter implementation. It is clamped so it can never push a
// note back past the finger; a ±20-tick jitter on a 2-tick delay would otherwise sound
// BEFORE the touch that caused it.
//
// THE ALTERNATIVE, AND WHY IT WAS NOT TAKEN. The textbook fix is a fixed half-grid
// lookahead: delay EVERYTHING by span/2, then round to true nearest. That gives real
// nearest-neighbour quantization, needs no asymmetry and no echoes at all, and trades the
// per-note variable hold for one constant latency. It is the right answer for a recording
// path — and the wrong one here, because this surface is an INSTRUMENT: at 120 BPM on a
// sixteenth grid it would add a flat ~62 ms between finger and sound, well past the ~20–30 ms
// where touch stops feeling attached to the hand. A player can learn constant latency on a
// keyboard they hear through a monitor; they cannot un-feel it on a screen they are touching.
// So the asymmetry stays, and the cost is honest: an early note is held by a varying amount,
// up to half a grid step. If a future slice adds a "studio" mode for recording rather than
// playing, the lookahead is the design to reach for.
//
// Pure value logic — Foundation only, no UIKit, no audio, no engine — so every boundary
// above is unit-tested on CI without an Apple UI stack, the same law as RollFitMath and
// FloatingVisualLayout. Quantization happens BEFORE the lock-free enqueue to the voice;
// nothing here ever runs on the audio thread.

import Foundation

/// What to do with one touch. `play` is the untouched case (correction off, already on the
/// grid, or a late note with echoes disabled).
public enum TouchQuantizeAction: Equatable, Sendable {
    /// Sound it exactly where the finger landed.
    case play(atTick: Int)
    /// Hold it back onto (or toward) the grid point ahead.
    case delay(toTick: Int)
    /// Too late to move: sound it now, and put the pulse back with an echo on the grid.
    ///
    /// `echoVelocityScale` is what makes this a DELAY and not a doubled note. At 1.0 the
    /// echo is a second full note and the part thickens; at ~0.5 the ear parses it as a
    /// ghost — an effect answering the mistake rather than a mistake of its own. It also
    /// carries `strength`, which is what keeps that knob continuous on this branch: without
    /// it, easing strength up from zero would pull early notes gently and hard-double the
    /// late ones the instant it left 0.
    case playThenEcho(atTick: Int, echoTick: Int, echoVelocityScale: Float)

    /// When the note is first HEARD. Deliberately not "the tick" — for `playThenEcho` the
    /// echo is a second, later event, and callers scheduling the voice need the first one.
    public var soundingTick: Int {
        switch self {
        case let .play(t):                 return t
        case let .delay(t):                return t
        case let .playThenEcho(t, _, _):   return t
        }
    }

    /// The follow-up event, if this action has one.
    public var echoTick: Int? {
        if case let .playThenEcho(_, echo, _) = self { return echo }
        return nil
    }
}

public struct TouchQuantizer: Sendable, Equatable {

    /// Musical grid. Spans are exact at the shared 480-PPQ resolution — including the
    /// triplets, which divide the quarter evenly (3 × 160, 6 × 80). A grid that did not
    /// divide the quarter would drift against the bar over a few bars of playing.
    public enum Grid: String, CaseIterable, Identifiable, Sendable {
        case quarter, eighth, sixteenth, eighthTriplet, sixteenthTriplet

        public var id: String { rawValue }

        public var tickSpan: Int {
            switch self {
            case .quarter:          return TimelineTime.ticksPerQuarter          // 480
            case .eighth:           return TimelineTime.ticksPerQuarter / 2      // 240
            case .sixteenth:        return TimelineTime.ticksPerQuarter / 4      // 120
            case .eighthTriplet:    return TimelineTime.ticksPerQuarter / 3      // 160
            case .sixteenthTriplet: return TimelineTime.ticksPerQuarter / 6      // 80
            }
        }

        public var label: String {
            switch self {
            case .quarter:          return "1/4"
            case .eighth:           return "1/8"
            case .sixteenth:        return "1/16"
            case .eighthTriplet:    return "1/8T"
            case .sixteenthTriplet: return "1/16T"
            }
        }
    }

    public var grid: Grid
    /// How far a touch is pulled toward the grid. 0 = off (the tick is returned untouched),
    /// 1 = fully on the grid. A non-finite or out-of-range value reads as OFF: half-applying
    /// a broken number would leave the instrument subtly, unexplainably out of time.
    public var strength: Float
    /// Whether a late touch gets its pulse restored by an echo on the next grid point.
    public var echoesLateNotes: Bool
    /// How late a touch may be and still count as ON the grid — no correction, no echo.
    ///
    /// WITHOUT THIS the type had a discontinuity that punished good players. A touch one
    /// tick late — about a millisecond at 120 BPM, far below anything a human can hear as
    /// separate — produced a whole extra note, while a touch exactly on the tick produced
    /// none. Since "late" means anywhere in the first half of a grid interval, that fired an
    /// echo on roughly HALF of all touches: not a delay effect, a doubled part. And the
    /// tighter someone plays, the more of their notes land *just* late.
    ///
    /// 12 ticks ≈ 12.5 ms at 120 BPM, under the ~20–30 ms at which two onsets separate into
    /// distinct events, and inside the ~10–20 ms timing spread of a trained player. So the
    /// echo now answers a real mistake and stays silent on a good take.
    public var latenessToleranceTicks: Int
    /// Level of the echo relative to the note that caused it. At 1.0 it is a second full
    /// note (the part thickens); around 0.5 the ear hears a ghost, i.e. a delay. Scaled by
    /// `strength` at plan time, which is what keeps that knob continuous on the late branch.
    public var echoLevel: Float
    /// Optional per-note offset so a quantized run breathes instead of sitting on a machine
    /// grid. `.tight` (the default) means no offset at all.
    public var microtiming: Humanizer

    public init(grid: Grid = .sixteenth,
                strength: Float = 0,
                echoesLateNotes: Bool = true,
                latenessToleranceTicks: Int = 12,
                echoLevel: Float = 0.5,
                microtiming: Humanizer = .tight) {
        self.grid = grid
        self.strength = strength
        self.echoesLateNotes = echoesLateNotes
        self.latenessToleranceTicks = latenessToleranceTicks
        self.echoLevel = echoLevel
        self.microtiming = microtiming
    }

    /// Effective strength: NaN/inf and anything outside 0…1 collapse to 0 (off).
    private var safeStrength: Float {
        guard strength.isFinite, strength > 0 else { return 0 }
        return Swift.min(1, strength)
    }

    /// Decide what to do with a touch at `tick`.
    ///
    /// - Parameters:
    ///   - tick: when the finger landed, in 480-PPQ ticks on whatever timeline the caller
    ///     anchors to. A NEGATIVE tick is passed through untouched — it means the caller's
    ///     anchor has not started yet, and inventing a grid position for it would be worse
    ///     than doing nothing.
    ///   - index: the note's index within the take, for reproducible microtiming.
    ///   - seed: the take's seed, so the same performance replays with the same feel.
    public func plan(forTick tick: Int, index: Int = 0, seed: UInt64 = 0) -> TouchQuantizeAction {
        let s = safeStrength
        let span = grid.tickSpan
        guard s > 0, span > 0, tick >= 0 else { return .play(atTick: tick) }

        let previous = (tick / span) * span
        let offset = tick - previous
        if offset == 0 { return .play(atTick: tick) }        // already exactly on the grid
        let next = previous + span

        // Which grid point is nearer? `offset` is the distance PAST the previous point, so
        // the distance to the next one is `span - offset`, and the touch is early exactly
        // when `span - offset <= offset` — i.e. `2 * offset >= span`, kept in integers.
        //
        // A TIE (`2 * offset == span`) counts as EARLY on purpose: resolving it toward the
        // previous point would ask for a note to move backwards, the one thing this type may
        // never do. Writing that inequality the other way round is the easy mistake — it
        // reads plausibly and inverts the whole behaviour, delaying late notes and echoing
        // early ones.
        let isEarly = 2 * offset >= span

        if isEarly {
            // Pull toward the grid point ahead. Partial strength lands between the touch and
            // the grid; rounding is fine here because both ends are >= tick.
            let pulled = Float(next - tick) * s
            let target = tick + Int(pulled.rounded())
            let breathed = applyMicrotiming(to: target, floor: tick, index: index, seed: seed)
            return breathed == tick ? .play(atTick: tick) : .delay(toTick: breathed)
        }

        // Late. The note has already been heard as far as the player is concerned, so it
        // sounds where it landed; the grid is restored by the echo instead of by force.
        //
        // …but only if it is late ENOUGH to be a mistake. Inside the tolerance the touch
        // counts as on the grid and passes straight through — see `latenessToleranceTicks`
        // for why the version without this check doubled roughly half of everything played.
        let tolerance = Swift.max(0, Swift.min(latenessToleranceTicks, span / 2))
        guard echoesLateNotes, offset > tolerance else { return .play(atTick: tick) }

        // The echo breathes too. Leaving it dead on the grid while the DELAYED notes get
        // microtiming would be backwards: the echo is the one purely synthetic event here
        // and the one that most needs not to sound machine-placed.
        let echoTick = applyMicrotiming(to: next, floor: tick + 1, index: index &+ 1, seed: seed)
        let level = (echoLevel.isFinite ? echoLevel : 0).clamped(to: 0...1) * s
        return .playThenEcho(atTick: tick, echoTick: echoTick, echoVelocityScale: level)
    }

    /// Seeded per-note offset, clamped so it can never precede `floor` (the touch itself).
    /// The clamp is the point: without it a ±20-tick jitter applied to a 2-tick delay lands
    /// the note 18 ticks BEFORE the finger that played it.
    private func applyMicrotiming(to target: Int, floor: Int, index: Int, seed: UInt64) -> Int {
        guard microtiming.isActive else { return target }
        let delta = microtiming.jitter(index: index, seed: seed).tickDelta
        return Swift.max(floor, target + delta)
    }
}
