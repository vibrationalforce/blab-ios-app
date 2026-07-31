// ExpressionLevelTrim.swift
// Echoel — the play surface's vertical axis chooses colour and octave, NOT loudness.
//
// Pure Foundation value math, no Core/Sequencer types (`DSP/` hygiene, project.yml).

import Foundation

/// THE DEFECT THIS CORRECTS, and the founder diagnosed it correctly (2026-07-29):
/// *"die Sounds sind teilweise unterschiedlich laut, das liegt evtl. daran, dass einige
/// dunkler sind und gefiltert"*.
///
/// The play surface's vertical axis drives **two** things at once, stacking in the SAME
/// direction: the octave band (bottom = lowest) and the filter morph (bottom = darkest,
/// 0.66×…1.52× at the default depth 0.6 — 1.2 octaves of cutoff). So the bottom-left of the
/// surface is the lowest AND most filtered note there is, and the top-right the highest AND
/// brightest. Nothing in this app compensated: there is no key tracking and no filter
/// make-up gain. The morph is meant to be a COLOUR control; it was silently also a LOUDNESS
/// control.
///
/// ⛔ **THIS MOVED HERE FROM `TouchPitchMap.levelCompensation` (#230), AND THE MOVE IS THE
/// WHOLE POINT — do not put it back on the velocity.** The first version multiplied the
/// note's VELOCITY at note-on. That evened the STRIKE and left the DRAG untouched: a finger
/// held on one degree and pulled bottom→top sweeps the full 1.2 octaves of cutoff through
/// `EchoelPolyDDSP.setNoteCutoffScale`, and velocity is not addressable on a sounding note.
/// Half the gesture the surface is built for got no correction at all. Here the engine holds
/// one trim PER VOICE next to `voiceCutoffScale`, recomputed at every writer of pitch or
/// cutoff (spawn · slide · continuous morph), so the drag is corrected exactly like the strike.
///
/// ⛔ **AND IT FIXES A SECOND, QUIETER ERROR THE VELOCITY VERSION COULD NOT.** Velocity is not
/// amplitude: `spawnVoice` applies `pow(velocity, expo)` with `expo = 1 + percussiveness × 0.5`,
/// so a −1.8 dB velocity trim DELIVERED −1.8 dB on a slow pad and up to −2.6 dB on a percussive
/// one — the correction's size depended on the patch. This gain is applied in the amplitude
/// domain (the render's pan gains), so the delivered dB is the computed dB for every patch.
///
/// **Direction: this only ever CUTS, never boosts, and that is a hard safety property.**
/// Lifting the quiet notes cannot work: `velocity` tops out at 0.95 and Life multiplies it by
/// up to 1.04, leaving ~1.2 % of headroom before the engine's clamp — any real boost would pin
/// every firm touch at the ceiling, the flat-fortissimo failure `microVariation`'s own comment
/// records having shipped once. So the reference is the patch's neutral (`cutoffScale` 1 at
/// `referencePitch`): brighter/higher notes are pulled DOWN toward the dark ones, and the dark
/// ones — the ones that sounded too quiet — keep their full level.
///
/// ⚠️ **SAY THIS PLAINLY TO WHOEVER READS THE COMPLAINT NEXT: the notes the founder called too
/// quiet receive exactly 0 dB of help.** The surface is evened by lowering the loud end onto
/// them, which makes the surface as loud as its quietest note — a real answer to "angleichen",
/// but not the only possible one, and it costs overall level. The `touch.level` control (a
/// genuine gain on this voice, default 1.0) is where that comes back. Boosting the dark end
/// instead would need a static make-up on the VOICE, and that is the shape of the next slice
/// if the ear says the surface got too quiet.
///
/// ⚠️ **THE CONSTANTS ARE ESTIMATES AND NEED AN EAR.** The review of the first version showed
/// they were mis-apportioned rather than merely uncertain, and both were changed without a
/// single test going red — which is exactly the limit these tests state about themselves:
///   · The filter term was 2.5 dB/oct. The voice is additive harmonics through a 2-pole
///     (12 dB/oct) lowpass whose cutoff sits 4–40× above the fundamental for EVERY factory
///     patch, so doubling the cutoff adds only a few percent of energy. The app's own
///     `SynthPatch.loudnessEstimate` agrees by omission: it has no `filterCutoff` term at all.
///   · The pitch term was 1.5 dB/oct. ISO 226 across this surface's actual register
///     (130…523 Hz) falls roughly 4–5 dB/octave. **Pitch is the dominant cause, not the
///     filter** — the opposite of the first version's weighting.
public enum ExpressionLevelTrim {

    /// Loudness rise per octave of FILTER cutoff. Deliberately small — see the note above.
    public static let filterLoudnessDbPerOctave: Double = 1.0

    /// Perceptual tilt with PITCH — the DOMINANT term (ISO 226 across 130…523 Hz). Still under
    /// the physical figure on purpose: bass sitting a little softer than treble is normal and
    /// wanted in a mix, and only the part that reads as "different instrument loudness" is
    /// being removed.
    public static let pitchLoudnessDbPerOctave: Double = 3.0

    /// How much of the computed imbalance is removed. Not 1.0: a surface where every note is
    /// *exactly* as loud reads as synthetic.
    ///
    /// ⚠️ It was 0.5 while the trim rode on VELOCITY, where `pow(v, expo)` silently multiplied
    /// the delivered dB by 1.0…1.5 depending on the patch. In the amplitude domain that
    /// multiplier is gone, so 0.5 here delivers LESS than 0.5 did on a percussive patch. It is
    /// kept at 0.5 anyway, and the reason is a rule this file already states: under-correcting
    /// is the safe direction, and the constants are for an ear at a device, not for a
    /// compensating arithmetic guess. Whoever runs that listening test changes THIS number.
    public static let evenness: Double = 0.5

    /// Hard floor, so no extreme cutoff can mute a note. NOT reachable from the engine's own
    /// cutoff clamp (0.1…8 gives at most about −1.5 dB through the filter term at these
    /// weights) — it is a backstop for a corrupted preset or a future bio mapping.
    public static let floorGain: Double = 0.35

    /// A gain in `(0, 1]` that takes the loudness side-effect out of a note's brightness and
    /// register. Applied in the AMPLITUDE domain (`EchoelPolyDDSP`'s render pan gains).
    ///
    /// - Parameters:
    ///   - cutoffScale: the note's filter scale, 1 = the patch's own cutoff.
    ///   - pitch: MIDI note number.
    ///   - referencePitch: the pitch that gets no trim. The play surface passes its OWN middle
    ///     band (`key.degree(d, octave: 4)`), which in A sits ~9 semitones above C — a fixed
    ///     C4 would make the whole surface about 1 dB quieter in A than in C for no musical
    ///     reason. The trim must depend on where a note sits ON THE SURFACE, not on the key.
    public static func gain(cutoffScale: Float, pitch: Int, referencePitch: Int) -> Float {
        guard evenness > 0 else { return 1 }
        let s = Double(cutoffScale)
        guard s.isFinite, s > 0 else { return 1 }
        // How many dB this note is expected to sound ABOVE the reference. Negative for the
        // dark, low notes — and those are then left alone by the `min(1, …)` below.
        let aboveReferenceDb = filterLoudnessDbPerOctave * Foundation.log2(s)
            + pitchLoudnessDbPerOctave * Double(pitch - referencePitch) / 12.0
        guard aboveReferenceDb.isFinite else { return 1 }
        let g = pow(10.0, -(aboveReferenceDb * evenness) / 20.0)
        // NaN-safe by argument order (`max(0.35, NaN)` returns 0.35, `max(NaN, 0.35)` returns
        // NaN) on top of the explicit `isFinite` fallback. Cut-only via `min(1, …)`.
        return Float(min(1.0, max(floorGain, g.isFinite ? g : 1)))
    }
}
