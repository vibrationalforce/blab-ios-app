//
//  TouchInstrumentView.swift
//  Echoelmusic — Studio
//
//  The immersive visual as a PLAYABLE multi-touch instrument (founder
//  2026-07-07: "Vielleicht lässt sich sogar das Visual in ein Multi-Touch
//  Instrument umwandeln. Mit mehreren Fingern wird je nach Position, Fläche
//  und Druck passend zum Sound gespielt … wie wenn man mit den Fingern durchs
//  Wasser geht").
//
//  Coherence by construction: every touch is quantized into the take's
//  MusicalKey (root + scale) and voiced by the SAME PolySynthVoice patch the
//  generative loop plays — so whatever the fingers do, it belongs to the sound.
//  X = scale degree across one octave · Y = octave band (low/mid/high) ·
//  contact AREA (majorRadius) and PRESSURE (force, where the hardware has it)
//  = velocity. Slides glide through the scale like trailing a hand in water.
//
//  Render safety: pure UIKit for INPUT only — touch handling never touches
//  SwiftUI state, and (structural rebuild 2026-07-09) the water-ripple feedback
//  is NO LONGER Core Animation at all: every drop goes into TouchRippleChannel
//  and is drawn by the Metal shader inside the immersive field itself. One
//  pipeline, one clock, one drawable — the artifact class of a second compositor
//  layered over the Metal drawable (mismatched frames on any move/resize, layer
//  pop, animation-clock edges) is gone by construction. Sound goes through
//  PolySynthVoice.noteOn/noteOff, which are lock-free SPSC enqueues.
//
//  Water feel (founder: "es soll sich nach echtem Wasser anfühlen"): a touch is
//  a DROP — a colour cloud that blooms and dissolves like ink in water, with one
//  thin wavefront ring as its leading edge, in the played note's physical colour.
//

import Foundation

/// Pure touch→music mapping — Foundation-only (no UIKit/CoreGraphics), so it
/// unit-tests without an Apple UI stack.
public enum TouchPitchMap {
    /// Octave bands bottom→top. Around the composer's pad register (padOctave
    /// ~3–4, lead ~5): low third of the surface = 3, middle = 4, top = 5.
    public static let octaveBands = [3, 4, 5]

    /// Map a normalized touch position (x 0…1 left→right, y 0…1 BOTTOM→TOP)
    /// into a scale-quantized MIDI pitch. X spans one octave of scale degrees;
    /// Y picks the octave band — always inside the key, never a wrong note.
    public static func pitch(normX: Double, normY: Double, key: MusicalKey) -> Int {
        let n = max(1, key.degreesPerOctave)
        let x = min(max(normX, 0), 0.999_999)
        let y = min(max(normY, 0), 1)
        let degree = Int(x * Double(n))
        let band = min(octaveBands.count - 1, Int(y * Double(octaveBands.count)))
        return key.degree(degree, octave: octaveBands[band])
    }

    /// Velocity from contact: whichever of pressure (0…1, 0 where the hardware
    /// has no force sensing) and contact radius (points; fingertip ≈ 8, flat
    /// finger ≈ 25+) says MORE intent wins. Floor keeps a feather touch audible.
    /// Range lifted 2026-07-07 (founder: "der Sound … könnte sich im mix ein bisschen
    /// mehr durchsetzen") so a played note sits slightly ON TOP of the generative loop
    /// instead of under it — feather ≈ 0.45, firm ≈ 0.95 (was 0.35 / 0.85).
    public static func velocity(forceNorm: Double, radiusPoints: Double) -> Float {
        let area = min(max((radiusPoints - 6) / 22, 0), 1)
        let intent = max(min(max(forceNorm, 0), 1), area)
        return Float(min(max(0.45 + 0.5 * intent, 0.3), 0.95))
    }

    /// MICRO-VARIATION — the difference between a sampler and an instrument (founder
    /// 2026-07-27: "Alles soll nie statisch gleich klingend sein sondern leben wie ein
    /// echtes Instrument mit micro changes"). Two identical taps on the same tile must
    /// not produce two identical notes: a real string, reed or hammer never repeats
    /// itself exactly, and the ear reads perfect repetition as machinery.
    ///
    /// Returns multiplicative deviations for the two dimensions that already have
    /// per-note plumbing — filter brightness and velocity — so this rides the MPE path
    /// rather than adding a second one.
    ///
    /// DETERMINISTIC, NOT RANDOM: a counter-based integer hash (SplitMix64's finalizer),
    /// so the sequence never repeats within a performance but a test can pin it exactly.
    /// `Math.random` in a signal path is untestable and unreviewable; a seeded sequence
    /// is both. It also means no allocation and no RNG state to share across threads.
    ///
    /// `depth` 0 returns exactly (1, 1) — the old behaviour, bit-identical, so the
    /// setting genuinely switches the feature off rather than merely reducing it.
    public static func microVariation(noteIndex: UInt64, depth: Double)
        -> (cutoffScale: Float, velocityScale: Float) {
        let d = min(max(depth.isFinite ? depth : 0, 0), 1)
        guard d > 0 else { return (1, 1) }
        // SplitMix64 finalizer — strong avalanche, no state, pure integer arithmetic.
        func mix(_ x: UInt64) -> UInt64 {
            var z = x &+ 0x9E37_79B9_7F4A_7C15
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        /// [-1, 1) from the top 53 bits of an independent stream.
        ///
        /// The divisor MUST match the shift: `h >> 11` leaves 53 significant bits, so the
        /// scale is 2^53. It said 2^52, which made the ratio span [0, 2) and the result
        /// [-1, 3) — a one-sided distribution three times too wide on the positive side.
        /// That is not cosmetic: it let `velocityScale` reach 1.12, and 0.95 × 1.12 = 1.064
        /// pins at `finish()`'s velocity clamp, i.e. this feature re-created the exact
        /// flat-fortissimo failure the mixer cap was written to remove. Caught by
        /// `testMicroVariation_staysWithinAudibleAndSafeBounds`, which is why that test
        /// asserts the product `0.95 * velocityScale < 1.0` and not just the factor.
        func bipolar(_ h: UInt64) -> Double { Double(h >> 11) / Double(1 << 53) * 2 - 1 }
        let hCut = mix(noteIndex &* 2)
        let hVel = mix(noteIndex &* 2 &+ 1)
        // Brightness moves more than level: an instrument's timbre varies audibly note to
        // note while its loudness under one steady touch does not. Bounds are deliberately
        // small — ±6% cutoff and ±4% velocity at full depth. Velocity stays clear of the
        // 1.0 clamp because `TouchPitchMap.velocity` tops out at 0.95 (0.95 × 1.04 = 0.988).
        return (Float(1 + bipolar(hCut) * 0.06 * d),
                Float(1 + bipolar(hVel) * 0.04 * d))
    }

    /// A slide re-triggers only when it crosses into a new quantized pitch —
    /// jitter inside one degree must NOT machine-gun the note.
    public static func slideRetriggers(oldPitch: Int, newPitch: Int) -> Bool {
        oldPitch != newPitch
    }

    /// POSITION MORPH (founder 2026-07-08: "Der Sound … soll auch morphbar sein.
    /// Je nachdem wo man sich befindet ändert sich der Sound"): the vertical
    /// position continuously morphs the touch voice's filter — low on the surface
    /// = darker/rounder, high = brighter/opener — riding ON TOP of the octave
    /// bands, so a slide upward both climbs the register AND opens the timbre,
    /// like a hand rising through water toward light. `depth` 0 = off (scale 1);
    /// depth 1 = ±1 octave of cutoff (0.5×…2×). Exponential so it's perceptually
    /// even; pure → unit-tested.
    public static func morphCutoffScale(normY: Double, depth: Double) -> Float {
        let y = min(max(normY.isFinite ? normY : 0.5, 0), 1)
        let d = min(max(depth.isFinite ? depth : 0, 0), 1)
        return Float(pow(2.0, (y - 0.5) * 2.0 * d))
    }

    // MARK: - Evenness (founder 2026-07-29: "die Sounds sind teilweise unterschiedlich laut")

    /// THE DEFECT THIS FIXES, and the founder diagnosed it correctly: *"das liegt evtl.
    /// daran, dass einige dunkler sind und gefiltert"*.
    ///
    /// The vertical axis of the play surface drives **two** things at once, and they stack in
    /// the SAME direction:
    ///   · `pitch(normX:normY:key:)` picks the octave band — bottom = lowest.
    ///   · `morphCutoffScale(normY:depth:)` picks the filter — bottom = darkest.
    /// At the default morph depth 0.6 the cutoff spans 0.66×…1.52×, i.e. **1.2 octaves of
    /// filter**, on top of two octaves of pitch. So the bottom-left of the surface is the
    /// lowest AND the most filtered note there is, and the top-right is the highest AND the
    /// brightest. That is not a patch quirk — it is structural, and nothing anywhere in this
    /// app compensated for it: there is no key tracking and no filter make-up gain.
    ///
    /// The morph is meant to be a COLOUR control. It was silently also a LOUDNESS control.
    ///
    /// ⚠️ TWO HONEST LIMITS on what this closes, both found in review:
    ///   · The horizontal axis is in scope too, not just the vertical one. X spans a scale
    ///     octave, so the pitch term also varies ACROSS a row — about 1 dB at these weights,
    ///     with the tonic at the left edge the loudest note in its row. That may well be
    ///     desirable; it is not what "vertical axis" implies, so it is written down.
    ///   · **The continuous morph is NOT corrected.** A finger held on one degree and dragged
    ///     bottom→top sweeps the full 1.2 octaves of cutoff through `setNoteCutoffScale`,
    ///     which writes only the filter — velocity is not addressable on a sounding note. So
    ///     this evens the STRIKE and leaves the DRAG exactly as uneven as before. Closing that
    ///     needs a per-voice trim inside the engine, where the cutoff, the register and the
    ///     velocity exponent are all known; that is the structurally correct home for this
    ///     whole correction and a bigger slice. Do not report the defect as closed.
    ///
    /// **Direction: this only ever CUTS, never boosts, and that is a hard safety property.**
    /// The obvious fix — lift the quiet notes — cannot work here: `velocity` tops out at 0.95
    /// and Life multiplies it by up to 1.04, leaving 1.2 % of headroom before the engine's
    /// clamp. Any real boost would pin every firm touch at the ceiling, which is exactly the
    /// flat-fortissimo failure `microVariation`'s own comment records having already shipped
    /// once. So the reference is the patch's neutral (`cutoffScale` 1, `referencePitch`):
    /// brighter or higher notes are pulled DOWN toward the dark ones, and the dark ones — the
    /// ones that sounded too quiet — keep their full level.
    ///
    /// ⚠️ **SAY THIS PLAINLY TO WHOEVER READS THE COMPLAINT NEXT: the notes the founder called
    /// too quiet receive exactly 0 dB of help.** The surface is evened by lowering the loud
    /// end onto them, which makes the surface as loud as its quietest note — a real answer to
    /// "angleichen", but not the only possible one, and it costs overall level. The `touch.level`
    /// control (a genuine gain on this voice, default 1.0) is where that comes back. Boosting
    /// the dark end instead would need a static make-up on the VOICE, not a per-note velocity
    /// factor, because per-note there is no headroom — that is the shape of the next slice if
    /// the ear says the surface got too quiet.
    ///
    /// ⚠️ **THE CONSTANTS ARE ESTIMATES AND NEED AN EAR**, and the review of the first version
    /// showed they were mis-apportioned rather than merely uncertain:
    ///   · The filter term was 2.5 dB/oct. The voice is additive harmonics through a 2-pole
    ///     (12 dB/oct) lowpass whose cutoff sits 4–40× above the fundamental for EVERY factory
    ///     patch, so doubling the cutoff adds only a few percent of energy — well under
    ///     1 dB/oct for harmonic-dominant patches. The app's own `SynthPatch.loudnessEstimate`
    ///     agrees by omission: it has no `filterCutoff` term at all.
    ///   · The pitch term was 1.5 dB/oct. ISO 226 across this surface's actual register
    ///     (130…523 Hz) falls roughly 4–5 dB/octave. **Pitch is the dominant cause, not the
    ///     filter** — the opposite of the first version's weighting.
    /// The corner total is deliberately kept near 3 dB while the split is corrected, so the
    /// shape and every safety property are unchanged and only the attribution moves.
    ///
    /// ⚠️ **WHAT THIS RETURNS IS A VELOCITY FACTOR, AND VELOCITY IS NOT AMPLITUDE.** The engine
    /// applies `amplitude = pow(velocity, expo)` with `expo = 1 + percussiveness × 0.5`
    /// (`EchoelPolyDDSP.spawnVoice`), and 19 of 21 factory patches are percussive enough to sit
    /// at `expo` ≈ 1.2…1.5. So a −1.8 dB velocity trim DELIVERS about −1.8 dB on a slow pad and
    /// up to −2.6 dB on a percussive patch. `evenness` is set against the percussive case
    /// because that is the common one; the pad under-corrects slightly, which is the safer
    /// direction. 0 = bit-identical to the old behaviour.
    public static let filterLoudnessDbPerOctave: Double = 1.0
    /// Perceptual tilt with PITCH — the DOMINANT term (ISO 226 across 130…523 Hz). Still under
    /// the physical figure on purpose: bass sitting a little softer than treble is normal and
    /// wanted in a mix, and only the part that reads as "different instrument loudness" is
    /// being removed.
    public static let pitchLoudnessDbPerOctave: Double = 3.0
    /// How much of the computed imbalance is removed. Not 1.0 for two reasons: a surface where
    /// every note is *exactly* as loud reads as synthetic, and the velocity→amplitude power
    /// above means the delivered correction is already larger than this number suggests.
    public static let evenness: Double = 0.5

    /// A velocity multiplier in `(0, 1]` that takes the loudness side-effect out of the note's
    /// brightness and register. Multiply the note's velocity by it.
    ///
    /// - Parameters:
    ///   - cutoffScale: the note's filter scale, 1 = the patch's own cutoff.
    ///   - pitch: MIDI note number.
    ///   - referencePitch: the pitch that gets no trim. Defaults to 60 (C4), but callers on the
    ///     play surface should pass the surface's OWN middle-band pitch: the band is
    ///     `key.degree(d, octave: 4)`, which in A averages ~9 semitones above C — so a literal
    ///     60 would make the whole surface about 1 dB quieter in A than in C, for no musical
    ///     reason. The trim must depend on where a note sits ON THE SURFACE, not on the key.
    public static func levelCompensation(cutoffScale: Float, pitch: Int,
                                         referencePitch: Int = 60) -> Float {
        guard evenness > 0 else { return 1 }
        let s = Double(cutoffScale)
        guard s.isFinite, s > 0 else { return 1 }
        // How many dB this note is expected to sound ABOVE the reference. Negative for the
        // dark, low notes — and those are then left alone by the `min(1, …)` below.
        let aboveReferenceDb = filterLoudnessDbPerOctave * Foundation.log2(s)
            + pitchLoudnessDbPerOctave * Double(pitch - referencePitch) / 12.0
        guard aboveReferenceDb.isFinite else { return 1 }
        let gain = pow(10.0, -(aboveReferenceDb * evenness) / 20.0)
        // NaN-safe by argument order (`max(0, x)` returns 0 for NaN, `max(x, 0)` returns NaN)
        // and cut-only. The 0.35 floor is a backstop for a corrupted preset or a future bio
        // mapping: it is NOT reachable from the engine's own cutoff clamp (0.1…8 gives at most
        // −1.5 dB through the filter term at these weights), only from an extreme cutoff and
        // an extreme register together. The first version of this comment claimed the clamp
        // alone reached the floor; that was arithmetic from the old, larger filter weight.
        return Float(min(1.0, max(0.35, gain.isFinite ? gain : 1)))
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// The touch instrument's OWN synth (founder 2026-07-08: presets/character must be
/// individually settable, and the play surface must not glitch the generative bed).
/// A dedicated PolySynthVoice instance means (a) touch notes never STEAL voices from
/// the generative loop mid-sustain — the "komische glitches" — and (b) the touch
/// sound can carry its own patch + position morph without re-patching the whole take.
/// nil (default) = fall back to the shared take voice (pre-wiring behaviour).
/// SwiftUI-only guard (no UIKit): EchoelmusicApp injects this on EVERY platform,
/// even where the UIKit play surface below doesn't compile (macOS CI).
private struct TouchSynthKey: EnvironmentKey {
    // Computed (not a stored `static let`): a stored non-Sendable static is a
    // Swift 6 strict-concurrency error; a computed nil default has no shared state.
    static var defaultValue: PolySynthVoice? { nil }
}

extension EnvironmentValues {
    var touchSynth: PolySynthVoice? {
        get { self[TouchSynthKey.self] }
        set { self[TouchSynthKey.self] = newValue }
    }
}

/// The dedicated LEAD voice (separate from the main `synth`/polyVoice), injected so the
/// Studio can reach it for per-track FX — the generated `.lead` notes play through it, so a
/// "Melodic" insert must cover it too. Same computed-default guard as TouchSynthKey.
private struct LeadSynthKey: EnvironmentKey {
    static var defaultValue: PolySynthVoice? { nil }
}

extension EnvironmentValues {
    var leadSynth: PolySynthVoice? {
        get { self[LeadSynthKey.self] }
        set { self[LeadSynthKey.self] = newValue }
    }
}
#endif

#if canImport(UIKit) && canImport(SwiftUI)
import UIKit

/// Where the beat is, at the instant one finger lands. Tick and tick-length are read
/// TOGETHER so they can never describe different tempos — the bug you get from passing
/// a tick down one path and a BPM down another while a tempo glide is in flight.
struct TouchMusicalTime {
    /// Song-absolute 480-PPQ tick under the finger.
    let tick: Int
    /// Wall-clock duration of one tick, for turning a tick distance into a delay.
    let secondsPerTick: Double
}

/// Transparent multi-touch layer mounted over the fullscreen immersive visual.
struct TouchInstrumentView: UIViewRepresentable {
    let key: MusicalKey
    let synth: PolySynthVoice
    /// ULTRASYNC. Default strength 0 = off, and the instrument behaves exactly as before.
    var quantizer = TouchQuantizer()
    /// Supplies the musical clock at touch time. `nil` (or a `nil` result) means "no
    /// grid" and every touch sounds immediately, uncorrected.
    ///
    /// `@MainActor` on the FUNCTION TYPE, not just on the closure literal: without it the
    /// type erases the isolation, and nothing would stop a later caller from invoking this
    /// off the main actor and touching `Transport` unsynchronized. Closing that while it
    /// costs nothing is cheaper than discovering it as a race.
    var musicalNow: (@MainActor () -> TouchMusicalTime?)?
    var reduceMotion: Bool = false
    /// Position-morph amount (0 = off … 1 = ±1 octave of filter travel).
    var morphDepth: Double = 0.6
    var lifeDepth: Double = 0.35
    /// Fretboard grid (founder 2026-07-08: "eine Art Griffbrett einblenden …
    /// Gitter mit Feldern in den passenden Farben"): show which note lives where.
    var showGrid: Bool = false
    /// Slide-expression depths + glide (founder 2026-07-08: "hin und her sliden
    /// verändert den Sound … Glide bzw. Portamento kann man auch einstellen").
    var slideVibrato: Double = 0.35
    var slideChorus: Double = 0.30
    var glide: Double = 0
    /// SELF-PLAY (founder 2026-07-29: *"Es soll auch eine Möglichkeit geben wie der Synth
    /// selbst spielt ohne das man Touch bedienen muss"*). `nil` = off, and OFF IS THE
    /// DEFAULT — this thing plays unattended, so it may never start on its own.
    var autoPlay: FieldAutoPlay.Params?
    /// Makes `.drift` reproducible. Same value → same figure.
    var autoPlaySeed: UInt64 = 0

    func makeUIView(context: Context) -> TouchInstrumentUIView {
        let v = TouchInstrumentUIView()
        v.synth = synth
        v.key = key
        v.reduceMotion = reduceMotion
        v.morphDepth = morphDepth
        v.lifeDepth = lifeDepth
        v.showGrid = showGrid
        v.slideVibrato = slideVibrato
        v.slideChorus = slideChorus
        v.glideSeconds = glide
        v.quantizer = quantizer
        v.musicalNow = musicalNow
        v.autoPlaySeed = autoPlaySeed
        // Set last so the seed is in place before the clock could ever look at it. The clock
        // does NOT start here — `startAutoPlay` requires a window and this view has none yet;
        // `didMoveToWindow` is what starts it. (An earlier comment on this line claimed the
        // `didSet` started it, which would have made the ordering load-bearing. It is not.)
        v.autoPlay = autoPlay
        return v
    }

    func updateUIView(_ uiView: TouchInstrumentUIView, context: Context) {
        uiView.key = key
        uiView.synth = synth
        uiView.reduceMotion = reduceMotion
        uiView.morphDepth = morphDepth
        uiView.lifeDepth = lifeDepth
        uiView.showGrid = showGrid
        uiView.slideVibrato = slideVibrato
        uiView.slideChorus = slideChorus
        uiView.glideSeconds = glide
        uiView.quantizer = quantizer
        uiView.musicalNow = musicalNow
        uiView.autoPlaySeed = autoPlaySeed
        uiView.autoPlay = autoPlay
    }
}

/// UIKit view doing the actual multi-touch → notes + water rings.
final class TouchInstrumentUIView: UIView {
    weak var synth: PolySynthVoice? {
        didSet {
            if synth !== oldValue {
                setNeedsGridRebuild()            // colours read its A4/cents
                applyExpressionSettings()        // depths/glide land on the new voice
            }
        }
    }
    var key = MusicalKey(root: 0, scale: .minor) {
        didSet { if key != oldValue { setNeedsGridRebuild() } }
    }
    var reduceMotion = false
    /// Position-morph amount for the vertical filter travel (0 = off).
    var morphDepth: Double = 0.6
    var lifeDepth: Double = 0.35
    /// Slide-expression depths (founder 2026-07-08: "hin und her sliden verändert
    /// den Sound: Filter, ein bisschen Vibrato, Chorus"): how much a travelling
    /// finger opens vibrato / ensemble on the touch voice. User-set in the
    /// Play-surface-sound menu; forwarded to the synth on change.
    var slideVibrato: Double = 0.35 {
        didSet { if slideVibrato != oldValue { applyExpressionSettings() } }
    }
    var slideChorus: Double = 0.30 {
        didSet { if slideChorus != oldValue { applyExpressionSettings() } }
    }
    /// Glide/portamento time (s). ≥ ~5 ms switches slides from retrigger to a
    /// true singing glide (same envelope, frequency slides).
    var glideSeconds: Double = 0 {
        didSet { if glideSeconds != oldValue { applyExpressionSettings() } }
    }

    private func applyExpressionSettings() {
        synth?.slideVibratoDepth = Float(min(max(slideVibrato, 0), 1))
        synth?.slideChorusDepth = Float(min(max(slideChorus, 0), 1))
        synth?.setPortamento(seconds: Float(min(max(glideSeconds, 0), 0.6)))
    }
    /// The fretboard grid — one field per playable note (columns = scale degrees,
    /// rows = octave bands), each tinted with ITS note's physical colour, exactly
    /// the mapping `pitch(at:)` uses. Display-only CALayers under the ripples.
    var showGrid = false {
        didSet { if showGrid != oldValue { setNeedsGridRebuild() } }
    }

    /// Sounding pitch per active touch. Capped so the play surface can never
    /// starve the generative loop of voices (PolySynthVoice steals oldest).
    private var held: [ObjectIdentifier: Int] = [:]
    /// Last per-note filter scale actually SENT for each finger. UIKit delivers touch
    /// moves at 60–120 Hz per finger; forwarding every one would push ~600 events/s into
    /// the lock-free note queue, which the render drains ~94×/s. Sending only audible
    /// changes keeps the queue far from its bound (#155) without any perceptible loss —
    /// a 1% cutoff step is well under a just-noticeable difference.
    private var lastSentMorph: [ObjectIdentifier: Float] = [:]
    /// Monotonic note counter feeding `TouchPitchMap.microVariation`. Wrapping is
    /// harmless — the hash has no structure at the wrap point, so note 2^64 sounds no
    /// more like note 0 than any other pair.
    private var noteCounter: UInt64 = 0
    /// ULTRASYNC (founder 2026-07-28). At `strength == 0` — the shipped default —
    /// `plan` returns the touch untouched and this whole path is bit-identical to the
    /// instrument before the feature existed.
    var quantizer = TouchQuantizer()
    /// Where the beat is, asked at the moment a finger lands.
    ///
    /// A closure rather than a `Transport` reference so this view stays testable and
    /// engine-free. (An earlier version of this comment called the alternative impossible
    /// — it is not: passing the object down is a capture, not a property read, and would
    /// be equally freeze-safe. What WOULD violate the freeze law is reading
    /// `transport.position` in a SwiftUI body to pass a VALUE down, and neither shape
    /// does that.) The reads happen inside the closure, at touch time, outside any
    /// observation tracking.
    /// `@MainActor` on the function TYPE so the isolation cannot be erased at a later
    /// call site and let someone reach `Transport` off the main actor.
    var musicalNow: (@MainActor () -> TouchMusicalTime?)?
    /// SELF-PLAY (#224, founder 2026-07-29: *"Es soll auch eine Möglichkeit geben wie der
    /// Synth selbst spielt ohne das man Touch bedienen muss"*). `nil` = off, and OFF IS THE
    /// DEFAULT: a generator that runs unattended must never start by itself.
    ///
    /// The generated contacts go through the SAME `sound(...)` dispatch a finger uses, so
    /// Ultrasync, Life and the evenness trim all apply to them and there is no second note
    /// path to drift (the #177 lesson, and the reason `FieldAutoPlay` emits POSITIONS).
    var autoPlay: FieldAutoPlay.Params? {
        didSet {
            // Only the on/off EDGE touches the clock — changing a dial mid-run must not
            // restart it, or every turn of a knob would re-align the phase to that moment.
            guard (autoPlay == nil) != (oldValue == nil) else { return }
            if autoPlay == nil { stopAutoPlay() } else { startAutoPlay() }
        }
    }
    /// Makes `.drift` reproducible; the other motions are fixed curves and ignore it.
    var autoPlaySeed: UInt64 = 0
    /// The cell the generator last acted on. `nil` = "next tick is a fresh start".
    private var lastFiredCell: Int?
    /// Stable synthetic "fingers" for generated notes, one per possible voice.
    ///
    /// `sound(...)` keys its held-back-note bookkeeping on a finger identity. A generated
    /// note has no `UITouch`, so it needs one — and it must be STABLE PER VOICE rather than
    /// fresh per note: with a fresh identity every cell, a voice re-firing before its own
    /// previous note landed would leave that pending note in the map with nothing that can
    /// ever cancel it. With a stable one, re-firing voice 2 replaces voice 2's own pending
    /// note and touches nobody else's — exactly how a finger behaves.
    private let autoPlayFingers: [NSObject] =
        (0..<FieldAutoPlay.maxVoices).map { _ in NSObject() }

    /// `CADisplayLink` RETAINS its target AND is retained by the run loop, which makes the
    /// naive version — link targeting the view — an immortal pair: the link keeps the view
    /// alive, so the view's `deinit` never runs, so nothing ever invalidates the link, and a
    /// surface nobody can see keeps ticking for the rest of the process.
    ///
    /// This proxy breaks it in BOTH directions. The run loop retains the proxy, the proxy
    /// holds the view WEAKLY, and the proxy owns the link — so the first tick after the view
    /// has gone invalidates the link and the whole thing is released. That is also why the
    /// view needs no `deinit`: cleanup does not depend on one running.
    @MainActor
    private final class AutoPlayProxy: NSObject {
        weak var view: TouchInstrumentUIView?
        var link: CADisplayLink?

        @objc func tick() {
            guard let view else {
                link?.invalidate()
                link = nil
                return
            }
            view.autoPlayTick()
        }

        func stop() {
            link?.invalidate()
            link = nil
        }
    }
    private let autoPlayProxy = AutoPlayProxy()

    private func startAutoPlay() {
        // `window != nil` is the whole lifetime rule in one place: the generator exists only
        // while the surface is on screen, and `didMoveToWindow` is what starts it otherwise.
        guard autoPlayProxy.link == nil, window != nil else { return }
        autoPlayProxy.view = self
        let link = CADisplayLink(target: autoPlayProxy, selector: #selector(AutoPlayProxy.tick))
        // 60 Hz, and the number is arithmetic rather than taste. This only has to NOTICE a
        // cell edge, but a look no faster than a cell silently drops notes — and the shortest
        // cell in the grid vocabulary is 1/16-triplet (80 ticks) at Transport's 300 BPM
        // ceiling, i.e. 33.3 ms, which is EXACTLY a 30 Hz look period. Critically sampled is
        // not "just enough": each cell then gets at most one look and rounding decides whether
        // it gets any — simulated, 30 Hz fires 46 of 61 cells. 60 Hz gives two looks per cell
        // at the worst setting the app allows and still survives a dropped frame.
        // `FieldAutoPlayDriverTests` pins the working case, the 30 Hz failure and the margin,
        // so this cannot be "optimised" back down without a red test.
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        autoPlayProxy.link = link
    }

    private func stopAutoPlay() {
        autoPlayProxy.stop()
        // Not a "resume from where we were" — the transport moved on meanwhile. The next
        // start begins on the next cell edge it sees.
        lastFiredCell = nil
    }

    /// One clock look. Cheap and boring on purpose: the decision is `FieldAutoPlay.cell`,
    /// which is pure and tested, and everything here is bookkeeping around it.
    fileprivate func autoPlayTick() {
        // Self-healing backstop, not the primary rule — `didMoveToWindow` is. If UIKit ever
        // tore the hierarchy down without that call, a generator on an off-screen surface
        // would be inaudible and unstoppable, so it costs one pointer check to make that
        // state impossible instead of merely unlikely.
        guard window != nil else { stopAutoPlay(); return }
        guard let params = autoPlay,
              let now = musicalNow?(), now.secondsPerTick > 0 else { return }
        // One cell = one grid step, reusing the Ultrasync vocabulary rather than inventing a
        // second time unit. Changing the grid therefore changes the self-play rate too, which
        // is the behaviour a player expects from one "grid" setting.
        let cell = FieldAutoPlay.cell(forTick: now.tick, ticksPerCell: quantizer.grid.tickSpan)
        guard cell != lastFiredCell else { return }
        lastFiredCell = cell

        // THE HAND ALWAYS WINS (founder's own metaphor: even with a finished soup people
        // want to feel they are cooking). While any finger is down the generator is silent —
        // not ducked, silent, and with no mode to find: put a finger down and it is yours.
        //
        // The cell is CONSUMED above rather than skipped, deliberately. Marking it fired
        // before this guard means lifting a hand does not dump the notes it silenced; play
        // simply resumes at the next cell edge.
        guard held.isEmpty else { return }

        // The cell's OWN tick, not the tick the display link happened to fire on. A generated
        // note is on the grid by construction; handing Ultrasync the look's tick made it
        // correct POLLING JITTER as if it were human lateness — at 1/16 / 120 BPM one dropped
        // frame put the offset past the ~20 ms tolerance, so the quantizer answered with an
        // echo on the next grid point, landing on top of the next cell's own note. That flam
        // is precisely what the tolerance exists to prevent.
        let onGridTick = cell * Swift.max(1, quantizer.grid.tickSpan)

        // The two surface facts the `.arp` motion needs, from the ONE place that owns them: the
        // key this very view maps with two lines below, and the surface's own band count. Read
        // here rather than defaulted inside the generator, because a mismatch there would be a
        // wrong DEGREE that still lands in the key — the kind no legality test can see.
        let touches = FieldAutoPlay.touches(atStep: cell, params: params, seed: autoPlaySeed,
                                            degreesPerOctave: key.degreesPerOctave,
                                            bandCount: TouchPitchMap.octaveBands.count)
        // The bound cannot bite today — `touches` returns at most `FieldAutoPlay.maxVoices`
        // and there is one finger per that — but it is the index guard for an array, and the
        // two caps living in different files is exactly how those drift apart.
        for (voice, t) in touches.enumerated() where voice < autoPlayFingers.count {
            let pitch = TouchPitchMap.pitch(normX: Double(t.x), normY: Double(t.y), key: key)
            let micro = TouchPitchMap.microVariation(noteIndex: noteCounter, depth: lifeDepth)
            let index = Int(truncatingIfNeeded: noteCounter)
            noteCounter &+= 1
            let cutoff = morphScale(normY: Double(t.y)) * micro.cutoffScale
            let even = TouchPitchMap.levelCompensation(cutoffScale: cutoff, pitch: pitch,
                                                       referencePitch: surfaceReferencePitch)
            sound(pitch: pitch,
                  velocity: t.velocity * micro.velocityScale * even,
                  cutoffScale: cutoff,
                  finger: ObjectIdentifier(autoPlayFingers[voice]), index: index,
                  autoRelease: true, onGridTick: onGridTick)
            // The picture follows a generated note exactly as it follows a finger. Without
            // this the field would play in visual silence — and `bandDrift` below its octave
            // threshold, which the generator documents as "moves the light, not the pitch",
            // would move nothing at all.
            showGeneratedNote(pitch: pitch, at: point(normX: Double(t.x), normY: Double(t.y)),
                              velocity: t.velocity)
        }
    }

    /// A generated contact's position in view coordinates, so it can drop a ring where a
    /// finger at that place would have. Mirrors `pitch(at:)`'s mapping in reverse.
    private func point(normX: Double, normY: Double) -> CGPoint {
        let rect = playRect
        return CGPoint(x: rect.minX + CGFloat(min(max(normX, 0), 1)) * rect.width,
                       y: rect.minY + CGFloat(1 - min(max(normY, 0), 1)) * rect.height)
    }

    /// Note-ons the quantizer is holding back, per finger.
    private var pendingOn: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Fingers that lifted while their note was still held back.
    ///
    /// The note is NOT dropped. Cancelling it was the first design and it made STACCATO
    /// PLAYING SILENTLY VANISH: at Sync 1 the hold is half a grid step — 62 ms on 1/16 at
    /// 120 BPM, 500 ms on 1/4 at 60 BPM — while a percussive tap lasts 50–100 ms. So the
    /// common case was a note the player felt (haptic), saw (ripple, colour) and never
    /// heard, indistinguishable from a dropout. A tap shorter than the hold is still a
    /// note that was played: it sounds ON the grid and releases itself right after.
    private var liftedWhilePending: Set<ObjectIdentifier> = []

    /// Is a pitch currently held by a finger whose note is actually SOUNDING?
    ///
    /// `held` alone cannot answer this, and conflating the two was a real stuck-note bug:
    /// `touchesBegan` writes `held[id]` before anything sounds, so a finger waiting out
    /// its hold made an echo's cleanup believe someone owned that pitch. The echo then
    /// skipped its own note-off, that finger lifted without sending one either (correctly
    /// — nothing had sounded), and the echo's voice was left in sustain with no owner.
    private func isSounding(pitch: Int) -> Bool {
        for (finger, p) in held where p == pitch && pendingOn[finger] == nil { return true }
        return false
    }
    private static let maxTouches = 4
    /// Last ring position per touch — a slide drops a new ring only every ~14 pt
    /// (a wake, not a smear).
    private var lastRing: [ObjectIdentifier: CGPoint] = [:]
    /// Last touch position per finger for the slide-expression gesture (every
    /// move event, unlike lastRing's 14 pt quantum).
    private var lastExprPos: [ObjectIdentifier: CGPoint] = [:]
    /// Host layer for the fretboard grid — sits UNDER the ripple layers.
    private let gridLayer = CALayer()
    private var gridBuiltForSize: CGSize = .zero
    private var gridDirty = true
    /// Per-note haptic (Vibration is a core Echoel dimension): a light impact on
    /// every note-on, intensity following the played velocity — the finger FEELS
    /// the note speak, which also makes the instrument playable without hearing.
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        // Water-ring layers must stay INSIDE the visual card: UIView does not clip
        // sublayers by default, so at the floating sizes rings near the edge were
        // drawn OVER the surrounding Studio UI (play-at-every-size made this visible).
        clipsToBounds = true
        isAccessibilityElement = true
        // The surface is called "Field" (founder 2026-07-29, rename delegated). This is the
        // one string a VoiceOver user hears for it, so it has to match the chip and the
        // panel heading exactly — a surface with two names is a surface nobody can be told
        // how to find. ⚠️ The `touch.*` AppStorage keys behind it are deliberately NOT
        // renamed: those persist, and renaming them would discard settings already dialled in.
        accessibilityLabel = "Field play surface"
        accessibilityHint = "Touch and slide to play notes in the current key"
        // DIRECT INTERACTION — the accessibility standard for musical instruments
        // (GarageBand model): a VoiceOver user double-taps the surface once, then
        // touches play IMMEDIATELY (no element-by-element navigation between the
        // fingers and the music). Combined with the note grid + per-note haptics,
        // the instrument is playable without sight.
        accessibilityTraits = [.allowsDirectInteraction]
        layer.addSublayer(gridLayer)   // first sublayer → ripples always render above
        hapticGenerator.prepare()
    }

    required init?(coder: NSCoder) { return nil }   // never instantiated from a nib

    // MARK: - Fretboard grid

    private func setNeedsGridRebuild() {
        gridDirty = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if gridDirty || gridBuiltForSize != bounds.size { rebuildGrid() }
    }

    /// The playable rect: bounds inset to the safe area. Fullscreen, the raw
    /// bounds run under the Dynamic Island / home indicator / rounded corners —
    /// the outermost grid columns rendered there but were physically cut off
    /// (founder screenshot 2026-07-09: "Also das adaptiv bitte"). Grid AND touch
    /// mapping share this rect so what you see is exactly what plays; in the
    /// floating window the insets are zero and nothing changes.
    private var playRect: CGRect {
        let r = bounds.inset(by: safeAreaInsets)
        return (r.width > 40 && r.height > 40) ? r : bounds
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsGridRebuild()
    }

    /// One field per playable note — columns = the key's scale degrees (X mapping),
    /// rows = the octave bands (Y mapping, bottom = low) — each filled + hairlined
    /// in ITS note's physical colour and labeled with the note name. Static
    /// display-only layers (rebuilt only on key/size/toggle change, never per
    /// frame or per touch), so the grid costs nothing while playing.
    private func rebuildGrid() {
        gridDirty = false
        gridBuiltForSize = bounds.size
        gridLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        gridLayer.frame = bounds
        // VoiceOver knows the terrain even without the visual grid: key, layout,
        // and how the surface is organised (kept current on every key change).
        let rootName = ["C", "C sharp", "D", "D sharp", "E", "F", "F sharp",
                        "G", "G sharp", "A", "A sharp", "B"][((key.root % 12) + 12) % 12]
        accessibilityValue = "Root \(rootName), \(key.degreesPerOctave) notes per octave, three octave rows, low at the bottom"
        guard showGrid, bounds.width > 60, bounds.height > 60 else { return }

        let rect = playRect                      // adaptive: never under notch/corners
        let n = max(1, key.degreesPerOctave)
        let bands = TouchPitchMap.octaveBands
        let cellW = rect.width / CGFloat(n)
        let cellH = rect.height / CGFloat(bands.count)
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let labelSize: CGFloat = min(12, max(9, cellH * 0.16))

        for d in 0..<n {
            for b in bands.indices {
                let pitch = key.degree(d, octave: bands[b])
                let tint = Self.noteTint(hz: frequency(of: pitch))
                let isRoot = d == 0
                // Band 0 is the LOW octave = BOTTOM row (UIKit y grows downward).
                let cellFrame = CGRect(x: rect.minX + CGFloat(d) * cellW,
                                       y: rect.maxY - CGFloat(b + 1) * cellH,
                                       width: cellW, height: cellH)
                    .insetBy(dx: 1.5, dy: 1.5)
                let cell = CALayer()
                cell.frame = cellFrame
                // AUTHENTIC READ: the fill deepens toward the LOW octave (bottom
                // row darkest — low notes carry more visual weight, like thick
                // strings) and the ROOT column is anchored with a stronger border,
                // the way every fretboard marks its tonal home. Fills stay subtle
                // so the living visual underneath remains the star.
                let octaveWeight = 0.14 - 0.03 * CGFloat(b)          // 0.14 · 0.11 · 0.08
                cell.backgroundColor = tint.withAlphaComponent(octaveWeight).cgColor
                cell.borderColor = tint.withAlphaComponent(isRoot ? 0.70 : 0.30).cgColor
                cell.borderWidth = isRoot ? 1.5 : 1
                cell.cornerRadius = 6
                gridLayer.addSublayer(cell)

                // Label: near-white for WCAG-solid contrast on the dark field (the
                // pure tint was unreadable for dim colours); the note's colour
                // stays on the field + border, so nothing is lost.
                let label = CATextLayer()
                label.string = names[((pitch % 12) + 12) % 12] + "\(pitch / 12 - 1)"
                label.fontSize = labelSize
                label.foregroundColor = UIColor.white.withAlphaComponent(isRoot ? 0.9 : 0.62).cgColor
                label.alignmentMode = .left
                label.contentsScale = window?.screen.scale ?? 3
                label.frame = CGRect(x: cellFrame.minX + 6,
                                     y: cellFrame.maxY - labelSize - 6,
                                     width: cellFrame.width - 8, height: labelSize + 3)
                gridLayer.addSublayer(label)
            }
        }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard held.count < Self.maxTouches else { break }
            let id = ObjectIdentifier(touch)
            let p = touch.location(in: self)
            let pitch = pitch(at: p)
            held[id] = pitch
            lastSentMorph[id] = morphScale(at: p)   // the note-on already carried this value
            let vel = velocity(of: touch)
            // This finger's OWN position travels with its note (MPE-style), instead of
            // being written to the instrument-wide scale where the next finger overwrote it.
            let micro = TouchPitchMap.microVariation(noteIndex: noteCounter, depth: lifeDepth)
            let noteIndex = Int(truncatingIfNeeded: noteCounter)
            noteCounter &+= 1
            // ULTRASYNC decides WHEN this sounds. Everything below — haptic, ripple,
            // colour — stays immediate on purpose: the finger must feel and see its own
            // touch with zero latency, and only the NOTE waits for the beat. That split
            // is what makes a held note playable instead of laggy.
            // EVENNESS: the vertical axis chooses colour and octave; it must not also choose
            // loudness (founder 2026-07-29). Cut-only, so a firm touch can never be pushed
            // into the engine's velocity clamp — see `levelCompensation`.
            let cutoff = morphScale(at: p) * micro.cutoffScale
            let even = TouchPitchMap.levelCompensation(cutoffScale: cutoff, pitch: pitch,
                                                       referencePitch: surfaceReferencePitch)
            sound(pitch: pitch, velocity: vel * micro.velocityScale * even,
                  cutoffScale: cutoff,
                  finger: id, index: noteIndex)
            hapticGenerator.impactOccurred(intensity: CGFloat(0.4 + 0.6 * Double(vel)))
            hapticGenerator.prepare()   // re-warm the Taptic engine so the NEXT note (tap or
                                        // slide-retrigger) fires with minimal latency — a play
                                        // surface triggers continuously, so it must never idle-sleep.
            // Playing feeds the picture: each note pumps excitation into the Metal
            // visual (swells intensity/motion), so the fingers visibly shape the light.
            TouchVisualEnergy.shared.excite(0.35)
            // The played tone becomes the picture's COLOUR (physical octave
            // transposition into visible light — performer priority in the renderer;
            // HELD, so a chord paints all its colours until the fingers lift).
            // CFAbsoluteTime — MUST match the draw loop's `nowGov` clock (CACurrentMediaTime
            // is a DIFFERENT epoch; mixing them would read every note as stale).
            TouchToneChannel.shared.noteOn(pitch: pitch, hz: frequency(of: pitch),
                                           at: CFAbsoluteTimeGetCurrent())
            spawnRing(at: p, strong: true, pitch: pitch, velocity: vel)
            lastRing[id] = p
            lastExprPos[id] = p
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let old = held[id] else { continue }
            let p = touch.location(in: self)
            // While ULTRASYNC still holds this finger's note back, nothing may address it:
            // a slide-retrigger would SOUND it early — the one thing the quantizer may
            // never do — and a cutoff push would address a note that is not playing. The
            // note keeps the pitch the finger LANDED on; an attack belongs to its landing
            // point.
            //
            // What this `continue` COSTS, stated because the first version of this comment
            // claimed the opposite: during the hold there is no wake ring and no slide
            // expression. `lastExprPos` is still advanced so the hold does not end in one
            // bogus travel spike; `lastRing` deliberately is NOT, so the 14 pt accumulator
            // survives and the wake resumes from where the finger actually is.
            if pendingOn[id] != nil {
                lastExprPos[id] = p
                continue
            }
            // CONTINUOUS morph while the finger travels — addressed to THIS finger's note.
            // `old` IS the sounding note (the guard above bound it) — no second lookup.
            let scale = morphScale(at: p)
            if abs(scale - (lastSentMorph[id] ?? 1)) > 0.01,
               synth?.setNoteCutoffScale(pitch: old, scale: scale) == true {
                lastSentMorph[id] = scale   // only once it is genuinely queued
            }
            // Slide-expression gesture (founder 2026-07-08: "hin und her sliden
            // verändert den Sound"): finger travel pumps vibrato/ensemble energy
            // into the touch voice; it decays (~0.45 s) when the finger rests and
            // clears when the fingers lift. Atomic param writes — touch-rate-safe.
            if let lp = lastExprPos[id] {
                let travel = Double(hypot(p.x - lp.x, p.y - lp.y))
                if travel > 0.5 {
                    synth?.pushSlideExpression(Float(min(0.35, travel / 320.0)))
                }
            }
            lastExprPos[id] = p
            let new = pitch(at: p)
            if TouchPitchMap.slideRetriggers(oldPitch: old, newPitch: new) {
                let vel = velocity(of: touch)
                if glideSeconds >= 0.005 {
                    // GLIDE (portamento on): the held voice keeps its envelope and
                    // SLIDES to the new pitch — no retrigger, a singing legato.
                    // Trimmed for consistency, but be clear about what it does: the engine
                    // KEEPS a glided note's struck level (`EchoelPolyDDSP.slideNote` never
                    // rewrites `amplitude`/`velocityGain` — legato by design), so this
                    // `velocity:` is ignored on a real glide. It bites only in `slideNote`'s
                    // `!moved` fallback, where the old voice is already gone and this becomes
                    // a fresh note-on. An earlier version of this comment claimed it stopped a
                    // level jump mid-slide; the engine cannot produce one.
                    let cutoff = morphScale(at: p)
                    synth?.slide(from: old, to: new,
                                 velocity: vel * TouchPitchMap.levelCompensation(
                                    cutoffScale: cutoff, pitch: new, referencePitch: surfaceReferencePitch),
                                 cutoffScale: cutoff)
                } else {
                    synth?.noteOff(pitch: old)
                    let micro = TouchPitchMap.microVariation(noteIndex: noteCounter, depth: lifeDepth)
                    noteCounter &+= 1
                    let cutoff = morphScale(at: p) * micro.cutoffScale
                    let even = TouchPitchMap.levelCompensation(cutoffScale: cutoff, pitch: new,
                                                               referencePitch: surfaceReferencePitch)
                    synth?.noteOn(pitch: new, velocity: vel * micro.velocityScale * even,
                                  cutoffScale: cutoff)
                }
                // Slides tick more softly than fresh strikes — a fret-crossing feel.
                hapticGenerator.impactOccurred(intensity: CGFloat(0.25 + 0.35 * Double(vel)))
                hapticGenerator.prepare()   // keep the Taptic engine warm through a slide's rapid ticks
                held[id] = new
                TouchVisualEnergy.shared.excite(0.15)   // slides keep the picture alive
                let now = CFAbsoluteTimeGetCurrent()
                TouchToneChannel.shared.noteOff(pitch: old, at: now)
                TouchToneChannel.shared.noteOn(pitch: new, hz: frequency(of: new), at: now)
            }
            // Wake trail — a small ring roughly every 14 pt of travel, in the colour
            // of the note the finger is sounding right now.
            if let last = lastRing[id], hypot(p.x - last.x, p.y - last.y) > 14 {
                spawnRing(at: p, strong: false, pitch: held[id] ?? old, velocity: velocity(of: touch))
                lastRing[id] = p
            }
        }
    }

    // MARK: - ULTRASYNC scheduling

    /// Sound one touch, in time. Falls back to an immediate note-on whenever there is
    /// no grid to quantize to — a stopped transport, or correction turned off — because
    /// holding a note back against a beat the player cannot hear is worse than not
    /// quantizing at all.
    ///
    /// - Parameters:
    ///   - autoRelease: the note has no finger and nothing will ever lift it — let it go by
    ///     itself after `staccatoSeconds`. Self-play's notes set this; a real touch never does,
    ///     because a real touch's release is its lift. This reuses the lifted-while-pending
    ///     behaviour that already exists rather than adding a second lifecycle.
    ///   - onGridTick: the tick Ultrasync should CORRECT AGAINST, when that differs from the
    ///     tick the note arrived on. A finger passes nil — it landed when it landed, and the
    ///     difference from the grid is the human timing being corrected. A generated note
    ///     passes its cell's start tick, because it is on the grid by construction and the only
    ///     thing "now" would measure is how late the display link woke up.
    private func sound(pitch: Int, velocity: Float, cutoffScale: Float,
                       finger id: ObjectIdentifier, index: Int,
                       autoRelease: Bool = false, onGridTick: Int? = nil) {
        guard let now = musicalNow?(), now.secondsPerTick > 0 else {
            // Unreachable for a generated note today — `autoPlayTick` already required a
            // musical clock and there is no suspension point between the two reads. Kept
            // because `sound` is called from four places and must be correct for all of them.
            synth?.noteOn(pitch: pitch, velocity: velocity, cutoffScale: cutoffScale)
            if autoRelease { scheduleSelfRelease(pitch: pitch) }
            return
        }
        // The echo tolerance is stored in TICKS, but "two onsets fuse into one" is a fact
        // about MILLISECONDS. 12 ticks is 12.5 ms at 120 BPM and only 5 ms at 300 — where
        // the echo would fire on nearly every late touch and land ~25 ms behind its parent,
        // i.e. a flam, which is precisely the doubled-part failure the tolerance exists to
        // prevent. Raising it to at least 20 ms of real time keeps the intent at any tempo.
        var q = quantizer
        q.latenessToleranceTicks = Swift.max(q.latenessToleranceTicks,
                                             Int((0.020 / now.secondsPerTick).rounded()))
        switch q.plan(forTick: onGridTick ?? now.tick, index: index) {
        case .play:
            synth?.noteOn(pitch: pitch, velocity: velocity, cutoffScale: cutoffScale)
            if autoRelease { scheduleSelfRelease(pitch: pitch) }

        case let .delay(toTick):
            // The hold is bounded by the quantizer (half a grid step) plus its microtiming
            // (up to `Humanizer.timingTicks`), and by Transport's 30…300 BPM clamp — worst
            // case a quarter grid at 30 BPM with Life at 1: 240 + 8 ticks ≈ 1.03 s.
            // Deliberately not capped further; a coarse grid IS the setting the player chose.
            let seconds = Double(Swift.max(0, toTick - now.tick)) * now.secondsPerTick
            guard seconds > 0.002 else {                 // below the jitter floor: just play it
                synth?.noteOn(pitch: pitch, velocity: velocity, cutoffScale: cutoffScale)
                if autoRelease { scheduleSelfRelease(pitch: pitch) }
                return
            }
            pendingOn[id] = Task { @MainActor [weak self] in
                // `catch { return }`, NOT `try?`: a cancelled sleep throws, and `try?`
                // would swallow that and play a note the teardown just cancelled.
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                // …and the `catch` alone is NOT enough, which is the subtle half. Once the
                // deadline has elapsed the sleep returns SUCCESSFULLY and `cancel()` is a
                // no-op — the continuation is merely queued on the main actor. Anything
                // running in that gap (a lift, a dismissal) would otherwise still get the
                // note. This guard is what closes it; there is no suspension point after
                // it, so the decision cannot go stale.
                guard let self, !Task.isCancelled else { return }
                self.pendingOn.removeValue(forKey: id)
                // `remove(id) != nil` FIRST because `||` short-circuits and the removal is the
                // point of the call, not the answer. (An earlier version of this comment
                // justified the order with "a generated finger that leaked into
                // liftedWhilePending" — that state is unreachable: the set is only written in
                // `release(_:)`, which iterates real `UITouch`es. The ordering is still right;
                // the reason given for it was not.)
                let lifted = (self.liftedWhilePending.remove(id) != nil) || autoRelease
                self.synth?.noteOn(pitch: pitch, velocity: velocity, cutoffScale: cutoffScale)
                guard lifted else { return }
                // The finger is already gone (or there never was one), so nothing else will
                // ever release this. It sounds on the grid — where the player aimed — and lets
                // go by itself. Routed through `scheduleSelfRelease` rather than an inline
                // sleep so BOTH unheld paths get the same ownership check; the inline version
                // was pitch-keyed and would cut a newer note on the same pitch.
                self.scheduleSelfRelease(pitch: pitch)
            }

        case let .playThenEcho(_, echoTick, level):
            synth?.noteOn(pitch: pitch, velocity: velocity, cutoffScale: cutoffScale)
            if autoRelease { scheduleSelfRelease(pitch: pitch) }
            let seconds = Double(Swift.max(0, echoTick - now.tick)) * now.secondsPerTick
            guard seconds > 0.002, let voice = synth else { return }
            // The echo is deliberately NOT tracked in `pendingOn`: a lift must not cancel
            // it. That is the point — the late note is answered on the beat whether or not
            // the finger is still down. When it is down, this re-articulates the same
            // pitch, which IS the "put the pulse back" gesture.
            //
            // `voice` is captured STRONGLY while `self` stays weak, because the note-off
            // below is the only thing that can ever end this voice: with `[weak self]`
            // alone, a view torn down inside the ghost window (closing the visual is
            // exactly when that happens) left the echo sounding forever.
            Task { @MainActor [weak self, voice] in
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                guard !Task.isCancelled else { return }
                voice.noteOn(pitch: pitch, velocity: velocity * level, cutoffScale: cutoffScale)
                // `try?` here, NOT `catch { return }` — the asymmetry is deliberate. Before
                // the note, cancellation must SUPPRESS it; before the release, cancellation
                // must not, or cancelling is how the note gets stuck.
                try? await Task.sleep(for: .seconds(Self.echoGhostSeconds))
                // Release unless a finger is SOUNDING that pitch (then its own lift ends
                // both). `self == nil` means the surface is gone, so nobody is holding
                // anything and the off must go out.
                guard self?.isSounding(pitch: pitch) != true else { return }
                voice.noteOff(pitch: pitch)
            }
        }
    }

    /// Which unheld note most recently claimed each pitch. See `scheduleSelfRelease`.
    private var unheldOwner: [Int: UInt64] = [:]
    private var unheldTokenCounter: UInt64 = 0

    /// Let a note nobody is holding go again. Used by self-play, where there is no finger
    /// whose lift could end the note.
    ///
    /// Captures `voice` STRONGLY while `self` stays weak, for the same reason the echo does:
    /// this note-off is the ONLY thing that can end this voice, so a view torn down in the
    /// meantime (closing the visual, exactly when it happens) must not take the release with
    /// it and leave the note sounding forever.
    ///
    /// ⚠️ THE TOKEN IS NOT BOOKKEEPING, IT IS THE FIX for a defect the first version shipped
    /// with. `EchoelDDSP.noteOff(note:)` releases EVERY voice on that note number, and
    /// `isSounding` only walks `held` — which generated notes never enter. So a pitch-keyed
    /// release could only ever protect a FINGER, never a second generated note. At the
    /// shipped defaults (1/16 at 120 BPM = 125 ms cells, `staccatoSeconds` 0.18) every repeat
    /// of a pitch was cut by its own predecessor's release after ~55 ms; and repeats are the
    /// common case, not an edge one — at the default span the travel advances about half a
    /// scale degree per cell, and `Motion.hold` is an offered mode that plays one pitch
    /// forever. The token makes "is this still my note" answerable; without it, it isn't.
    ///
    /// `isSounding` is still checked, for the other half: a finger that landed on this pitch
    /// meanwhile keeps its note — its own lift ends both.
    private func scheduleSelfRelease(pitch: Int) {
        guard let voice = synth else { return }
        unheldTokenCounter &+= 1
        let token = unheldTokenCounter
        unheldOwner[pitch] = token
        Task { @MainActor [weak self, voice] in
            // `try?`, not `catch { return }`: before a note, cancellation must suppress it;
            // before a RELEASE, cancellation must not, or cancelling is how a note sticks.
            try? await Task.sleep(for: .seconds(Self.staccatoSeconds))
            if let self {
                // A newer unheld note owns this pitch → it will end it. Ours is already gone,
                // swallowed by that note's own `noteOn` on the same voice.
                guard self.unheldOwner[pitch] == token else { return }
                guard !self.isSounding(pitch: pitch) else { return }
                self.unheldOwner.removeValue(forKey: pitch)
                self.releaseGeneratedColour(pitch: pitch)
            }
            // `self == nil` means the surface is gone: nobody holds anything, so the off MUST
            // go out. That is the one case where skipping the ownership check is correct.
            voice.noteOff(pitch: pitch)
        }
    }

    /// The picture must follow a self-played note exactly as it follows a finger — colour,
    /// excitation and a ring. Without this the field plays in silence visually, and
    /// `FieldAutoPlay`'s Band-drift dial is inert below its octave threshold: its documented
    /// sub-threshold behaviour ("moves the light, not the pitch") depends on there BEING a
    /// light. Reduce Motion is honoured by `spawnRing` itself.
    private func showGeneratedNote(pitch: Int, at p: CGPoint, velocity: Float) {
        TouchVisualEnergy.shared.excite(0.35)
        TouchToneChannel.shared.noteOn(pitch: pitch, hz: frequency(of: pitch),
                                       at: CFAbsoluteTimeGetCurrent())
        spawnRing(at: p, strong: true, pitch: pitch, velocity: velocity)
    }

    /// …and hand the colour back when that note ends, which is what `release(_:)` does for a
    /// finger. Skipped while a finger holds the same pitch — that finger's lift owns it.
    private func releaseGeneratedColour(pitch: Int) {
        guard !isSounding(pitch: pitch) else { return }
        TouchToneChannel.shared.noteOff(pitch: pitch, at: CFAbsoluteTimeGetCurrent())
    }

    /// How long an unheld echo rings before it is released. Short enough to read as a
    /// ghost rather than a second part, long enough to survive the patch's own attack.
    private static let echoGhostSeconds: Double = 0.28
    /// How long a note whose finger already lifted rings once it lands on the grid. A tap
    /// the player cut short should read as short, not as a held note.
    private static let staccatoSeconds: Double = 0.18

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    private func release(_ touches: Set<UITouch>) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            lastSentMorph.removeValue(forKey: id)
            // A finger that lifts while its note is still held back is NOT cancelled — it
            // is marked, so the note still sounds on the grid and then releases itself.
            // Cancelling was the first design and it silently swallowed staccato playing
            // (see `liftedWhilePending`). No note-off goes out here either way: nothing
            // has sounded yet, so an off would at best be a no-op and at worst cut another
            // finger's note on the same pitch.
            let isPending = pendingOn[id] != nil
            if isPending { liftedWhilePending.insert(id) }
            if let pitch = held.removeValue(forKey: id) {
                if !isPending { synth?.noteOff(pitch: pitch) }
                // Colour follows the fingers: lifting releases this note's cloud;
                // the last lift starts the ~1.2 s afterglow back to the bed. Sent even
                // for a cancelled note, because `touchesBegan` opened this cloud the
                // instant the finger landed — the picture never waits for the beat.
                TouchToneChannel.shared.noteOff(pitch: pitch, at: CFAbsoluteTimeGetCurrent())
            }
            lastRing.removeValue(forKey: id)
            lastExprPos.removeValue(forKey: id)
        }
        // All fingers lifted → the slide expression settles immediately (no
        // lingering vibrato/ensemble on the release tails).
        if held.isEmpty { synth?.clearSlideExpression() }
    }

    /// Leaving the window (exit fullscreen mid-touch, dismissal) must not leave
    /// notes hanging.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            // ⚠️ NO LONGER GATED ON `!held.isEmpty`, and that gate was a real hole once
            // self-play existed: a generated note has no finger, so `held` is empty by
            // definition and the whole cleanup — INCLUDING the `pendingOn` cancellation —
            // was skipped on dismissal. A held-back generated note then fired its note-on up
            // to ~1.03 s AFTER the surface was gone (the delay bound documented above) and
            // rang for `staccatoSeconds` on top. Everything below is idempotent, so running
            // it on a dismissal with no touches costs nothing and closes that.
            //
            // Held-back notes die with the window. The ECHO deliberately does not: it is
            // untracked, so one scheduled just before dismissal still fires — bounded,
            // because it releases itself after `echoGhostSeconds` and only when no finger
            // holds that pitch. Stated rather than implied, because "notes die with the
            // window" on its own would read as covering both, and it does not.
            //
            // The self-release tasks are untracked for the same reason as the echo, and are
            // bounded the same way: ≤ `staccatoSeconds`, and their `voice` capture is strong
            // so the note-off still goes out after the view is gone. That is the safe
            // direction — a cancelled release is a stuck note.
            stopAutoPlay()
            for work in pendingOn.values { work.cancel() }
            pendingOn.removeAll()
            liftedWhilePending.removeAll()
            for pitch in held.values { synth?.noteOff(pitch: pitch) }
            held.removeAll()
            lastSentMorph.removeAll()
            lastRing.removeAll()
            lastExprPos.removeAll()
            synth?.setCutoffScale(1)           // no lingering morph after dismissal
            synth?.clearSlideExpression()      // no lingering vibrato/ensemble either
            TouchVisualEnergy.shared.reset()   // no lingering swell after dismissal
            TouchToneChannel.shared.reset()    // colour hands back to the bed
            TouchRippleChannel.shared.reset()  // water settles instantly too
        }
    }

    /// Self-play follows the surface's own lifetime: it runs while the field is on screen and
    /// stops when it leaves. That is a REAL LIMIT, not an oversight — closing the floating
    /// visual stops the generator. Making it survive a closed window means an app-level driver
    /// and a second note path, which is a separate decision (see `PLAN_FIELD_SELFPLAY_WIRING`).
    ///
    /// Generated notes already sounding are NOT cut here: each carries its own release, so the
    /// worst case is one 0.18 s tail after dismissal. Cancelling them instead would need the
    /// pending map, and those tasks are deliberately untracked.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopAutoPlay() } else if autoPlay != nil { startAutoPlay() }
    }

    // MARK: - Mapping

    private func pitch(at p: CGPoint) -> Int {
        // Same rect as the drawn grid — a finger on a visible field always plays
        // THAT field; touches in the safe-area margin clamp to the edge notes.
        let rect = playRect
        let w = max(rect.width, 1), h = max(rect.height, 1)
        return TouchPitchMap.pitch(normX: Double((p.x - rect.minX) / w),
                                   normY: Double(1 - (p.y - rect.minY) / h),   // UIKit y is down; up = higher
                                   key: key)
    }

    private func velocity(of touch: UITouch) -> Float {
        let forceNorm = touch.maximumPossibleForce > 0
            ? Double(touch.force / touch.maximumPossibleForce) : 0
        return TouchPitchMap.velocity(forceNorm: forceNorm,
                                      radiusPoints: Double(touch.majorRadius))
    }

    /// The pitch at the MIDDLE of this surface, in this key — the note that gets no evenness
    /// trim. Computed from the surface's own mapping rather than assumed to be C4: the middle
    /// band is `key.degree(d, octave: 4)`, which sits ~9 semitones higher in A than in C. With
    /// a fixed reference the whole surface would be about 1 dB quieter in one key than in
    /// another, which is a level change with no musical cause.
    private var surfaceReferencePitch: Int {
        TouchPitchMap.pitch(normX: 0.5, normY: 0.5, key: key)
    }

    /// Vertical position → this touch's filter morph, RETURNED rather than applied
    /// (founder 2026-07-27: "mehr MPE vibes"). It used to call `setCutoffScale`, the
    /// instrument-wide scale — so with three fingers at three heights every note took the
    /// LAST finger's filter, which is the opposite of per-note expression and was invisible
    /// only because one finger is the common case. The value now rides with the note event
    /// and the engine holds it per voice; the global scale stays free for automation.
    ///
    /// `depth` 0 → 1 (neutral), so a disabled morph is bit-identical to no expression.
    private func morphScale(at p: CGPoint) -> Float {
        guard morphDepth > 0.001 else { return 1 }
        let rect = playRect
        let h = max(rect.height, 1)
        return morphScale(normY: Double(1 - (p.y - rect.minY) / h))   // UIKit y is down; up = brighter
    }

    /// The same morph from a NORMALISED height, for a generated contact that never had view
    /// coordinates. Split out rather than duplicated so a self-played note and a finger at
    /// the same height cannot ever get different filters.
    private func morphScale(normY: Double) -> Float {
        guard morphDepth > 0.001 else { return 1 }
        return TouchPitchMap.morphCutoffScale(normY: min(max(normY, 0), 1), depth: morphDepth)
    }

    /// Sounding frequency of a MIDI pitch at the take's concert pitch (the touch
    /// synth is tuned by the Studio, so read its live A4 — not a hardcoded 440).
    /// Includes the active tone system's per-pitch-class cents (Pythagorean, just,
    /// maqām …) — same formula as the synth's noteOn — so the colour octave is
    /// transposed from the frequency the ear actually hears, in every tuning.
    private func frequency(of pitch: Int) -> Double {
        let a4 = Double(synth?.poly.a4Hz ?? 440)
        let cents = Double(synth?.uiTuningCents[((pitch % 12) + 12) % 12] ?? 0)
        return a4 * pow(2.0, (Double(pitch) - 69.0 + cents / 100.0) / 12.0)
    }

    // MARK: - Water ripples (drawn by the Metal renderer — structural rebuild 2026-07-09)

    /// The grid's field tint in the note's physical colour (CIE fit, sRGB-encoded
    /// for UIKit with a small white lift so deep red/violet still reads on the
    /// dark field). Used ONLY by the static fretboard grid now — the animated
    /// water feedback no longer lives in Core Animation at all.
    private static func noteTint(hz: Double) -> UIColor {
        // Shared display encoding (SpectralColor.displayComponents) — the SAME
        // helper the piano-roll raster uses, so both grids recolour identically
        // when the Kammerton moves (founder 2026-07-12).
        let c = SpectralColor.displayComponents(forToneHz: hz)
        return UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
    }

    /// A touch is a drop of COLOURED LIGHT — pushed into `TouchRippleChannel` and
    /// DRAWN BY THE METAL SHADER inside the immersive field itself (founder
    /// 2026-07-09: "immer noch diese grafischen Fehler … strukturiere von Anfang
    /// an neu"). The old CAShapeLayer/CAGradientLayer animations lived in a SECOND
    /// compositor over the Metal drawable — two pipelines with independent clocks,
    /// which is exactly the artifact class the renderer-managed drawable work
    /// eliminated everywhere else. Now: one pipeline, one clock, one drawable —
    /// the water is frame-locked to the field by construction. This view keeps
    /// only input, sound, haptics and the static grid.
    private func spawnRing(at p: CGPoint, strong: Bool, pitch: Int, velocity: Float) {
        guard !reduceMotion else { return }
        let w = max(bounds.width, 1), h = max(bounds.height, 1)
        let rgb = SpectralColor.toneLinearRGB(forToneHz: frequency(of: pitch))
        // Equal-luminance light: normalize so every note's ripple glows visibly —
        // the shader's cloud luminance floor does not cover this additive light,
        // and raw deep-red/violet CMF output is otherwise near-invisible.
        let m = max(rgb.r, max(rgb.g, rgb.b))
        let s = m > 0.001 ? 0.9 / m : 1
        let vel = Double(velocity.clamped(to: 0...1))     // NaN-safe: NaN → dimmest ripple
        TouchRippleChannel.shared.drop(
            x: Float(p.x / w),
            y: Float(1 - p.y / h),                    // shader space: y up
            amp: Float((strong ? 0.5 : 0.28) * (0.6 + 0.4 * vel)),
            r: Float(rgb.r * s), g: Float(rgb.g * s), b: Float(rgb.b * s),
            duration: strong ? 1.0 : 0.65,
            // strong drives the channel's eviction policy: wake (trail) drops are
            // rate-capped and never evict a live light; only real strikes may
            // reuse the dimmest slot (artifact audit 2026-07-09 #2).
            strong: strong,
            // CFAbsoluteTime — MUST match the draw loop's frame clock (same epoch
            // rule as TouchToneChannel; CACurrentMediaTime would read as stale).
            at: CFAbsoluteTimeGetCurrent())
    }
}
#endif
