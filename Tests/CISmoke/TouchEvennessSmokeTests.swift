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
// ⚠️ WHAT THESE TESTS CAN AND CANNOT SETTLE. They pin the SHAPE and the SAFETY of the
// correction — monotone in the right direction, never boosting, bounded, NaN-proof,
// switchable off. They cannot tell you whether 2.5 dB/octave is the right number for this
// synth's spectrum: that is an ear at a device, and the constants are documented as estimates.
// A green run here means "this cannot clip, cannot flatten, cannot explode" — not "it sounds
// even". Do not report it as the latter.

import Foundation
import XCTest
@testable import Echoelmusic

final class TouchEvennessSmokeTests: XCTestCase {

    /// THE SAFETY PROPERTY, and the reason the correction cuts instead of lifting. `velocity`
    /// tops out at 0.95 and Life multiplies by up to 1.04 → 0.988, i.e. 1.2 % of headroom
    /// before the engine's velocity clamp. A compensation that BOOSTED would pin every firm
    /// touch at the ceiling — the flat-fortissimo failure this repo has already shipped once
    /// (see `microVariation`'s own comment). So: never above 1, at any input.
    func testTheCompensationNeverBoosts() {
        for cutoff in [Float(0.05), 0.1, 0.5, 0.66, 1, 1.52, 2, 8, 50] {
            for pitch in stride(from: 0, through: 127, by: 1) {
                let g = TouchPitchMap.levelCompensation(cutoffScale: cutoff, pitch: pitch)
                XCTAssertLessThanOrEqual(g, 1,
                    "cutoff \(cutoff) pitch \(pitch) → \(g): a boost can pin the velocity clamp")
                XCTAssertGreaterThan(g, 0, "a zero or negative gain is silence, not evenness")
            }
        }
    }

    /// …and it is BOUNDED below, so no extreme cutoff can mute a note. The engine clamps
    /// cutoff to 0.1…8, which alone reaches −9 dB through the filter term.
    func testTheCompensationIsBoundedBelow() {
        for cutoff in [Float(0.001), 0.1, 8, 1000] {
            for pitch in [0, 60, 127] {
                XCTAssertGreaterThanOrEqual(
                    TouchPitchMap.levelCompensation(cutoffScale: cutoff, pitch: pitch), 0.35)
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
                XCTAssertGreaterThanOrEqual(
                    TouchPitchMap.levelCompensation(cutoffScale: a, pitch: pitch),
                    TouchPitchMap.levelCompensation(cutoffScale: b, pitch: pitch),
                    "a brighter note kept MORE level than a darker one at pitch \(pitch)")
            }
        }
        for cutoff in cutoffs {
            for pitch in stride(from: 24, to: 108, by: 12) {
                XCTAssertGreaterThanOrEqual(
                    TouchPitchMap.levelCompensation(cutoffScale: cutoff, pitch: pitch),
                    TouchPitchMap.levelCompensation(cutoffScale: cutoff, pitch: pitch + 12),
                    "a higher octave kept MORE level than a lower one at cutoff \(cutoff)")
            }
        }
    }

    /// The DARK, LOW corner — the notes the founder heard as too quiet — must be left
    /// completely alone. If the correction touched them it would be making the reported
    /// problem worse while appearing to address it.
    func testTheQuietCornerIsLeftAtFullLevel() {
        // Bottom of the surface at the default morph depth: cutoff 0.66, low octave band.
        XCTAssertEqual(TouchPitchMap.levelCompensation(cutoffScale: 0.66, pitch: 48), 1)
        XCTAssertEqual(TouchPitchMap.levelCompensation(cutoffScale: 0.5, pitch: 36), 1)
        // Neutral — the patch's own cutoff at the reference pitch — is also untouched, which
        // is what makes this a trim of the extremes rather than an overall level change.
        XCTAssertEqual(TouchPitchMap.levelCompensation(cutoffScale: 1, pitch: 60), 1)
    }

    /// The bright, high corner must actually be corrected — a "fix" that changes nothing
    /// passes every safety test above while leaving the defect exactly where it was. The
    /// expected value is computed from the published constants rather than hard-coded, so
    /// retuning them on device does not falsely redden this; what is pinned is that the
    /// correction is REAL and lands in an audible-but-not-choking range.
    func testTheLoudCornerIsActuallyPulledDown() {
        let top = TouchPitchMap.levelCompensation(cutoffScale: 1.52, pitch: 72)
        XCTAssertLessThan(top, 0.95, "the bright, high corner was not corrected at all")
        XCTAssertGreaterThan(top, 0.6, "over −4.4 dB would read as choked, not even")

        let expectedDb = TouchPitchMap.filterLoudnessDbPerOctave * Foundation.log2(1.52)
            + TouchPitchMap.pitchLoudnessDbPerOctave
        let expected = pow(10.0, -(expectedDb * TouchPitchMap.evenness) / 20.0)
        XCTAssertEqual(Double(top), expected, accuracy: 1e-4)
    }

    /// Non-finite input cannot produce a non-finite gain. A cutoff scale is a product of the
    /// morph and Life, both of which take `Double` parameters that bio values will eventually
    /// feed; a single NaN reaching velocity is how this app has twice shipped silence
    /// (#29, #176).
    func testNonFiniteInputCannotProduceANonFiniteGain() {
        for cutoff in [Float.nan, .infinity, -.infinity, -1, 0] {
            let g = TouchPitchMap.levelCompensation(cutoffScale: cutoff, pitch: 60)
            XCTAssertTrue(g.isFinite, "cutoff \(cutoff) produced \(g)")
            XCTAssertTrue(g > 0 && g <= 1)
        }
    }
}
