// TouchEvennessSmokeTests.swift
// Echoel — the play surface's vertical axis chooses colour and octave, NOT loudness.
//
// FOUNDER, 2026-07-29: *"Play surface sound nochmal überarbeiten, die Sounds sind teilweise
// unterschiedlich laut, das liegt evtl. daran, dass einige dunkler sind und gefiltert."*
// The diagnosis was right, and the cause is structural rather than a patch quirk: ONE axis
// drives two things that stack in the same direction —
//   · `TouchPitchMap.pitch(normX:normY:key:)` picks the octave band, bottom = lowest;
//   · `TouchPitchMap.morphCutoffScale(normY:depth:)` picks the filter, bottom = darkest
//     (0.66×…1.52× at the default depth 0.6 — 1.2 octaves of cutoff).
// So the bottom of the surface is the lowest AND most filtered note there is. Nothing
// compensated: this app has no key tracking and no filter make-up gain anywhere.
//
// ⛔ THE CORRECTION MOVED (#230), AND THESE TESTS MOVED WITH IT. It used to be
// `TouchPitchMap.levelCompensation`, a factor multiplied into the note's VELOCITY at note-on.
// That evened the STRIKE and left the DRAG untouched — a finger held on one degree and pulled
// bottom→top sweeps the full 1.2 octaves through `setNoteCutoffScale`, and velocity is not
// addressable on a sounding note. It now lives in `ExpressionLevelTrim` and is applied per
// voice by `EchoelPolyDDSP` at every writer of pitch or cutoff. The pure-math tests below are
// unchanged in substance — same formula, same constants — and the last two are new: they pin
// the half the old home could not reach.
//
// ⚠️ WHAT THESE TESTS CAN AND CANNOT SETTLE. They pin the SHAPE and the SAFETY of the
// correction — monotone in the right direction, never boosting, bounded, NaN-proof,
// switchable off, and now also that the DRAG is corrected at all. They cannot tell you whether
// 1.0 and 3.0 dB/octave are the right numbers for this synth's spectrum: that is an ear at a
// device, and the constants are documented as estimates — an earlier review changed both of
// them without a single test going red, which is exactly the limit being stated.
// A green run here means "this cannot clip, cannot flatten, cannot explode" — not "it sounds
// even". Do not report it as the latter.

import Foundation
import XCTest
@testable import Echoelmusic

final class TouchEvennessSmokeTests: XCTestCase {

    private func trim(_ cutoff: Float, _ pitch: Int, ref: Int = 60) -> Float {
        ExpressionLevelTrim.gain(cutoffScale: cutoff, pitch: pitch, referencePitch: ref)
    }

    /// THE SAFETY PROPERTY, and the reason the correction cuts instead of lifting. `velocity`
    /// tops out at 0.95 and Life multiplies by up to 1.04 → 0.988, i.e. 1.2 % of headroom
    /// before the engine's velocity clamp. A compensation that BOOSTED would pin every firm
    /// touch at the ceiling — the flat-fortissimo failure this repo has already shipped once
    /// (see `microVariation`'s own comment). So: never above 1, at any input.
    ///
    /// It still matters in the amplitude domain, for a different reason: the render multiplies
    /// this into the pan gains, which are already equal-power — a factor above 1 there would
    /// push a voice past the level its velocity and the poly makeup gain agreed on.
    func testTheCompensationNeverBoosts() {
        for cutoff in [Float(0.05), 0.1, 0.5, 0.66, 1, 1.52, 2, 8, 50] {
            for pitch in stride(from: 0, through: 127, by: 1) {
                let g = trim(cutoff, pitch)
                XCTAssertLessThanOrEqual(g, 1,
                    "cutoff \(cutoff) pitch \(pitch) → \(g): a boost can pin the velocity clamp")
                XCTAssertGreaterThan(g, 0, "a zero or negative gain is silence, not evenness")
            }
        }
    }

    /// …and it is BOUNDED below, so no extreme cutoff can mute a note. Note what the floor is
    /// NOT: at the corrected weights the engine's own cutoff clamp (0.1…8) reaches only about
    /// −1.5 dB through the filter term, so the floor is a backstop for a corrupted preset or a
    /// future bio mapping, not a limit the surface can hit. The inputs below are deliberately
    /// outside the engine's clamp for that reason.
    func testTheCompensationIsBoundedBelow() {
        for cutoff in [Float(0.001), 0.1, 8, 1000] {
            for pitch in [0, 60, 127] {
                XCTAssertGreaterThanOrEqual(trim(cutoff, pitch),
                                            Float(ExpressionLevelTrim.floorGain))
            }
        }
    }

    /// THE ONE THAT MATTERS MUSICALLY: brighter must never come out louder than darker at the
    /// same pitch, and higher must never come out louder than lower at the same brightness.
    /// That monotonicity IS the founder's complaint expressed as a property.
    func testBrighterAndHigherAreNeverLeftLouder() {
        let cutoffs: [Float] = [0.5, 0.66, 0.8, 1, 1.25, 1.52, 2]
        for pitch in [36, 48, 60, 72, 84] {
            for (a, b) in zip(cutoffs, cutoffs.dropFirst()) {
                XCTAssertGreaterThanOrEqual(trim(a, pitch), trim(b, pitch),
                    "a brighter note kept MORE level than a darker one at pitch \(pitch)")
            }
        }
        for cutoff in cutoffs {
            for pitch in stride(from: 24, to: 108, by: 12) {
                XCTAssertGreaterThanOrEqual(trim(cutoff, pitch), trim(cutoff, pitch + 12),
                    "a higher octave kept MORE level than a lower one at cutoff \(cutoff)")
            }
        }
    }

    /// The DARK, LOW corner — the notes the founder heard as too quiet — must be left
    /// completely alone. If the correction touched them it would be making the reported
    /// problem worse while appearing to address it.
    func testTheQuietCornerIsLeftAtFullLevel() {
        // Bottom of the surface at the default morph depth: cutoff 0.66, low octave band.
        XCTAssertEqual(trim(0.66, 48), 1)
        XCTAssertEqual(trim(0.5, 36), 1)
        // Neutral — the patch's own cutoff at the reference pitch — is also untouched, which
        // is what makes this a trim of the extremes rather than an overall level change.
        XCTAssertEqual(trim(1, 60), 1)
    }

    /// The bright, high corner must actually be corrected — a "fix" that changes nothing
    /// passes every safety test above while leaving the defect exactly where it was. The
    /// expected value is computed from the published constants rather than hard-coded, so
    /// retuning them on device does not falsely redden this; what is pinned is that the
    /// correction is REAL and lands in an audible-but-not-choking range.
    func testTheLoudCornerIsActuallyPulledDown() {
        let top = trim(1.52, 72)
        XCTAssertLessThan(top, 0.95, "the bright, high corner was not corrected at all")
        XCTAssertGreaterThan(top, 0.6, "over −4.4 dB would read as choked, not even")

        let expectedDb = ExpressionLevelTrim.filterLoudnessDbPerOctave * Foundation.log2(1.52)
            + ExpressionLevelTrim.pitchLoudnessDbPerOctave
        let expected = pow(10.0, -(expectedDb * ExpressionLevelTrim.evenness) / 20.0)
        XCTAssertEqual(Double(top), expected, accuracy: 1e-4)
    }

    /// The reference pitch must MOVE the neutral point, not decorate the signature. Without
    /// it the trim is anchored at C4 while the surface's own middle band is `key.degree(d,
    /// octave: 4)` — about 9 semitones higher in A than in C — so the whole surface would be
    /// roughly 1 dB quieter in one key than another, a level change with no musical cause.
    func testTheReferencePitchMovesTheNeutralPoint() {
        // At its own reference, a neutral-brightness note is always untouched, whatever key.
        for ref in [55, 60, 69, 72] {
            XCTAssertEqual(trim(1, ref, ref: ref), 1)
        }
        // And raising the reference must LOOSEN the trim on a given note, never tighten it.
        let atC4 = trim(1, 72, ref: 60)
        let atA4 = trim(1, 72, ref: 69)
        XCTAssertLessThan(atC4, atA4, "a higher reference must trim a given note less")
        XCTAssertLessThanOrEqual(atA4, 1)
    }

    /// Non-finite input cannot produce a non-finite gain. A cutoff scale is a product of the
    /// morph and Life, both of which take `Double` parameters that bio values will eventually
    /// feed; a single NaN reaching a render gain is how this app has twice shipped silence
    /// (#29, #176).
    func testNonFiniteInputCannotProduceANonFiniteGain() {
        for cutoff in [Float.nan, .infinity, -.infinity, -1, 0] {
            let g = trim(cutoff, 60)
            XCTAssertTrue(g.isFinite, "cutoff \(cutoff) produced \(g)")
            XCTAssertTrue(g > 0 && g <= 1)
        }
    }

    // MARK: - The engine half (#230) — the drag, which the velocity version could not reach

    #if canImport(Accelerate)

    /// Render one sustained note and report its peak. Same seed, same everything — the only
    /// variable across calls is what the caller did to the engine.
    private func peak(_ poly: EchoelPolyDDSP, blocks: Int = 8, frames: Int = 256) -> Float {
        var l = [Float](repeating: 0, count: frames)
        var r = [Float](repeating: 0, count: frames)
        var maximum: Float = 0
        for _ in 0..<blocks {
            poly.renderStereo(left: &l, right: &r, frameCount: frames)
            for i in 0..<frames { maximum = Swift.max(maximum, Swift.abs(l[i])) }
        }
        return maximum
    }

    /// OFF BY DEFAULT, AND OFF MEANS OFF. The generated take shares this engine and passes
    /// `cutoffScale: 1`, so a trim enabled there would silently re-balance every generated note
    /// against a reference nobody chose.
    ///
    /// ⛔ THE FIRST VERSION OF THIS TEST COULD NOT FAIL, and it is worth saying why because the
    /// shape is a common one: it rendered TWO DEFAULT engines and asserted they matched. That
    /// tests determinism, not off-ness — flip the default from −1 to 0 (trim ON, reference
    /// C-1, every note crushed) and both engines still match. It is a comparison against the
    /// ON state that carries the property, so that is what this does now.
    func testTheTrimIsOffUnlessASurfaceAsksForIt() {
        let plain = EchoelPolyDDSP(maxVoices: 4)
        let asked = EchoelPolyDDSP(maxVoices: 4)
        XCTAssertEqual(plain.expressionTrimReferencePitch, -1, "the default must be OFF")
        asked.expressionTrimReferencePitch = 60

        let alsoPlain = EchoelPolyDDSP(maxVoices: 4)
        for poly in [plain, asked, alsoPlain] {
            poly.noteOn(note: 84, velocity: 0.8, cutoffScale: 1.52)
        }
        // `peak` ADVANCES the engine, so each of these is read exactly once.
        let plainPeak = peak(plain)
        let askedPeak = peak(asked)
        let alsoPlainPeak = peak(alsoPlain)

        // Non-vacuity first: a comparison between two silences would satisfy everything below.
        XCTAssertGreaterThan(plainPeak, 0, "the engine rendered nothing — this test proves nothing")
        // A bright note two octaves above the reference: the trim has real work to do here, so
        // "unchanged" can only mean the default did not apply it.
        XCTAssertLessThan(askedPeak, plainPeak,
                          "asking for the trim changed nothing — the wiring does not reach the render")
        XCTAssertEqual(plainPeak, alsoPlainPeak, accuracy: 0,
                       "two default engines must still render bit-identically")
    }

    /// THE DEFECT #230 NAMES, AS A PROPERTY. A finger stays on one degree and travels upward:
    /// only `setNoteCutoffScale` fires, velocity is untouchable. Before this fix the note got
    /// brighter and louder with nothing to stop it. Now the engine re-trims the sounding voice,
    /// so the same drag must end up QUIETER than it does with the trim off.
    func testTheDragIsTrimmedOnASoundingNote() {
        let trimmed = EchoelPolyDDSP(maxVoices: 4)
        let untrimmed = EchoelPolyDDSP(maxVoices: 4)
        trimmed.expressionTrimReferencePitch = 60

        for poly in [trimmed, untrimmed] {
            poly.noteOn(note: 84, velocity: 0.8, cutoffScale: 0.66)   // struck at the bottom
            _ = peak(poly, blocks: 2)                                  // let the envelope open
            poly.setNoteCutoffScale(note: 84, scale: 1.52)             // dragged to the top
        }
        let after = peak(trimmed)
        let before = peak(untrimmed)
        XCTAssertLessThan(after, before,
            "the drag reached the bright end with no correction — that IS the #230 defect")
        // …and it must not overcorrect into a hole. The computed trim at (1.52, 84) is the
        // ASYMPTOTE of what this may cost; anything below it means something else is scaling
        // too. Asymptote and not equality because the render eases the trim over ~40 ms
        // (`voiceLevelTrimSmoothed` — an instant step here was a 1.5 dB click on a glide), so
        // over these eight blocks the measured value sits ABOVE the target, never below it.
        let expected = trim(1.52, 84)
        XCTAssertGreaterThan(after, before * expected * 0.9,
            "the trimmed drag lost more level than the published gain accounts for")
    }

    /// A GLIDE MOVES THE PITCH, SO IT MUST MOVE THE TRIM. `slideNote` deliberately keeps the
    /// note's struck level (legato), which is exactly why the trim has to be recomputed there:
    /// otherwise gliding up an octave arrives louder than striking the same note.
    func testAGlideCarriesTheTrimToItsNewPitch() {
        let glided = EchoelPolyDDSP(maxVoices: 4)
        let untrimmed = EchoelPolyDDSP(maxVoices: 4)
        glided.expressionTrimReferencePitch = 60      // origin pitch 60 = the neutral point

        for poly in [glided, untrimmed] {
            poly.noteOn(note: 60, velocity: 0.8, cutoffScale: 1)
            _ = peak(poly, blocks: 2)                 // let the envelope open at the origin
            poly.slideNote(from: 60, to: 84, velocity: 0.8, cutoffScale: 1)
        }
        // The trim at the ORIGIN is exactly 1 (neutral cutoff at the reference pitch), so any
        // difference here can only come from the slide having carried the trim to pitch 84.
        XCTAssertLessThan(peak(glided), peak(untrimmed),
            "a glide up two octaves kept its origin's level — the trim did not travel")
    }

    #endif
}
