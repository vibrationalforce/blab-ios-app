// GainLatchRecoveryTests.swift
// Echoel — #295 / #296 / #297. Blocking bundle.
//
// ⭐ ONE BUG SHAPE, FOUR PLACES, AND #294 WAS THE MILDEST OF THEM. The shape is a persistent
// one-pole with a re-seed guard written as `if x < 0 { x = seed }`. It reads like a recovery
// path and is not one: `NaN < 0` is FALSE, so the guard that exists to re-seed is exactly the
// guard that never fires when it is needed. Once poisoned, `x` stays poisoned — `NaN * 0.99`
// is still NaN — for the lifetime of the voice.
//
// ⚠️ THE OBSERVABLE FAILURE IS SILENCE, NOT NaN, AND THAT IS WHY THESE TESTS MEASURE A PEAK.
// `render` ends with a pre-reverb guard (`for i … where !buffer[i].isFinite { buffer[i] = 0 }`),
// so a poisoned voice never emits NaN to the outside — it emits ZEROS, forever, while every
// control still reads healthy. Asserting `isFinite` on the buffer would therefore pass both
// before and after the fix. The property that actually distinguishes them is: after the bad
// value goes away, does sound come BACK?
//
// The four members, and why `smoothedGain` was the severe one:
//   • `smoothedGain` (#295) — `sample = mixed * smoothedGain * envelopeValue`, so it zeroes
//     EVERY sample, and unlike the others nothing downstream clamped it. It also survived
//     note-off, note-on and a fresh patch apply, because `prepareForNote` resets only
//     `smoothedFreq`. Permanent silence with no way back short of relaunching the app.
//   • `smoothedHarmonicity` + `smoothedNoiseLevel` (#296) — `harmonicity` is written RAW by
//     `ResolvedPatch.apply` on the patch-only path, and `noiseLevel`'s bio line is
//     `Swift.max(0, …)`, a floor with no ceiling that +inf walks straight through.
//   • `vibratoPhase` (#297) — the `> 0` gate rejects NaN by position but ADMITS +inf; the wrap
//     test `> 2π` is then true while `inf - 2π` is still inf, and `sin(inf)` is NaN.
//
// ⚠️ NO DEMONSTRATED PRODUCER — saying so is part of the finding, exactly as in
// `FilterCutoffClampTests`. This is hardening with the same standing as #92 and #294, NOT a
// tuning change, and must never be reported as one. The "nothing that ships is touched" half
// is asserted at the bottom rather than asserted by assertion.

import Foundation
import XCTest
@testable import Echoelmusic

final class GainLatchRecoveryTests: XCTestCase {

    /// Loudest absolute sample over `blocks` render blocks. The accumulators glide with a
    /// coefficient of 0.01 (≈100-sample time constant), so 4096 samples is ~40 time constants —
    /// far more than recovery needs, and short enough to stay a unit test.
    private func peak(_ synth: EchoelDDSP, blocks: Int = 8, frames: Int = 512) -> Float {
        var buffer = [Float](repeating: 0, count: frames)
        var loudest: Float = 0
        for _ in 0..<blocks {
            synth.render(buffer: &buffer, frameCount: frames)
            for sample in buffer { loudest = Swift.max(loudest, abs(sample)) }
        }
        return loudest
    }

    private func voicing() -> EchoelDDSP {
        let synth = EchoelDDSP()
        synth.noteOn(frequency: 220)
        return synth
    }

    // MARK: - The premise

    /// ⚠️ EVERY TEST BELOW COMPARES AGAINST "IT MAKES SOUND AT ALL". If this one reddens, the
    /// others are measuring nothing and their greens mean nothing — so it is asserted rather
    /// than assumed.
    func testAHealthyVoiceMakesSound() {
        XCTAssertGreaterThan(peak(voicing()), 0, """
        a freshly triggered default voice rendered pure silence. The recovery tests below are \
        all "peak > 0 after the poison is removed", so they would pass vacuously — fix this \
        premise first, do not relax the others.
        """)
    }

    // MARK: - #295 master gain

    /// ⭐ THE ONE THAT MATTERS. `amplitude` is a bare `public var` with two writers; on the
    /// pure-patch path (no bio running) nothing clamps it. Poison it, then set it back to a
    /// perfectly ordinary value: sound must return.
    func testMasterGainRecoversAfterANonFiniteAmplitude() {
        for poison in [Float.nan, Float.infinity, -Float.infinity] {
            let synth = voicing()
            synth.amplitude = poison
            _ = peak(synth, blocks: 4)          // let the smoother latch
            synth.amplitude = 0.5               // an entirely healthy value again
            XCTAssertGreaterThan(peak(synth, blocks: 8), 0, """
            after a \(poison) amplitude the voice stayed silent even once amplitude was back \
            at 0.5. `smoothedGain` latched: its `< 0` re-seed cannot fire on NaN, and nothing \
            downstream clamps it, so every sample was zeroed by the render guard from then on. \
            This is the permanent-silence shape (#22/#29) and it is silent in the logs too.
            """)
        }
    }

    /// The gain latch outlived a whole note cycle, because `prepareForNote` resets only
    /// `smoothedFreq`. Retriggering is what a user would try first, and it did not help.
    func testANewNoteDoesNotClearAPoisonedGain() {
        let synth = voicing()
        synth.amplitude = .nan
        _ = peak(synth, blocks: 4)
        synth.noteOff()
        synth.prepareForNote()
        synth.amplitude = 0.5
        synth.noteOn(frequency: 330)
        XCTAssertGreaterThan(peak(synth, blocks: 8), 0, """
        a fresh note on a voice whose gain smoother had been poisoned produced silence. \
        Retriggering is the first thing a player tries, and before #295 it did nothing — \
        `prepareForNote` resets `smoothedFreq` and nothing else.
        """)
    }

    /// The patch door: `SynthPatch.outputLevel` comes from `decodeIfPresent`, so a truncated
    /// or hand-edited save can carry anything. `apply(to:)` writes it straight into
    /// `patchOutputLevel`, which is why the sanitiser sits on that property.
    func testAPatchWithANonFiniteOutputLevelStillSounds() {
        var poisoned = SynthPatch.factory[0]
        poisoned.outputLevel = Float.nan   // `Optional<Float>` has no `.nan` — spell it out
        let synth = voicing()
        poisoned.resolved().apply(to: synth)
        XCTAssertTrue(synth.patchOutputLevel.isFinite, """
        `patchOutputLevel` is \(synth.patchOutputLevel) after applying a patch whose \
        `outputLevel` was NaN. It multiplies the master-gain TARGET, so the smoother would \
        have nothing finite to converge on — clamping the accumulator alone would land it at \
        zero and hold it there.
        """)
        XCTAssertGreaterThan(peak(synth, blocks: 8), 0, """
        a patch carrying a NaN `outputLevel` silenced the voice permanently.
        """)
    }

    // MARK: - #296 character smoothers

    /// `harmonicity` and `noiseLevel` are written raw by `ResolvedPatch.apply`; their bio
    /// clamps only exist while bio is running.
    func testCharacterSmoothersRecoverAfterANonFiniteWrite() {
        for poison in [Float.nan, Float.infinity] {
            let harmonic = voicing()
            harmonic.harmonicity = poison
            _ = peak(harmonic, blocks: 4)
            harmonic.harmonicity = 0.88
            XCTAssertGreaterThan(peak(harmonic, blocks: 8), 0, """
            a \(poison) `harmonicity` left the voice silent after the value was healthy again. \
            `smoothedHarmonicity` multiplies the harmonic bank AND its complement scales the \
            noise bed, so a poisoned one takes the whole mix with it.
            """)

            let noisy = voicing()
            noisy.noiseLevel = poison
            _ = peak(noisy, blocks: 4)
            noisy.noiseLevel = 0.01
            XCTAssertGreaterThan(peak(noisy, blocks: 8), 0, """
            a \(poison) `noiseLevel` left the voice silent after the value was healthy again.
            """)
        }
    }

    // MARK: - #297 vibrato phase

    /// The gate reads `vibratoRate > 0 && vibratoDepth > 0`, which screens NaN by position and
    /// lets +inf through — and an infinite phase cannot be wrapped back by subtracting 2π.
    func testAnInfiniteVibratoDoesNotPoisonThePitch() {
        for poison in [Float.infinity, -Float.infinity] {
            let synth = voicing()
            synth.vibratoDepth = 0.5
            synth.vibratoRate = poison
            XCTAssertGreaterThan(peak(synth, blocks: 4), 0, """
            a \(poison) vibrato rate silenced the voice. The phase accumulates to infinity, \
            `sin(inf)` is NaN, and the NaN reaches `currentFreq` — every partial's phase is \
            poisoned from that sample on.
            """)
            synth.vibratoRate = 5                // an ordinary musical vibrato
            XCTAssertGreaterThan(peak(synth, blocks: 8), 0, """
            the voice stayed silent after the vibrato rate was healthy again — `vibratoPhase` \
            is cleared only by `reset()`, never by `prepareForNote`, so a stuck phase outlives \
            every note.
            """)
        }
    }

    // MARK: - Nothing that ships is touched

    /// ⚠️ THE HALF THAT IS EASY TO CLAIM AND EASY TO SKIP — and the ledger records a dead-end
    /// where a sentinel was picked WITHOUT measuring the palette first. A bound added to catch
    /// impossible values must be provably invisible to every value people actually produce.
    func testNoShippedPatchComesNearEitherBound() {
        for entry in shippedPatches {
            // Master gain: `amplitude` is ≤ 1 on both writers, so the worst product a patch
            // can reach is its own level.
            XCTAssertLessThan(entry.patch.level, EchoelDDSP.masterGainRange.upperBound, """
            \(entry.label) has an output level of \(entry.patch.level), at or above the \
            master-gain ceiling \(EchoelDDSP.masterGainRange.upperBound). The clamp would start \
            SHAPING that patch instead of only catching impossible values — a tuning change \
            wearing a robustness fix's clothes.
            """)
            XCTAssertTrue(EchoelDDSP.characterRange.contains(entry.patch.harmonicity), """
            \(entry.label) has harmonicity \(entry.patch.harmonicity), outside \
            \(EchoelDDSP.characterRange) — the character smoother would clamp a real preset.
            """)
            XCTAssertTrue(EchoelDDSP.characterRange.contains(entry.patch.noiseLevel), """
            \(entry.label) has noiseLevel \(entry.patch.noiseLevel), outside \
            \(EchoelDDSP.characterRange).
            """)
        }
    }

    /// A healthy voice must still converge on exactly `amplitude * patchOutputLevel` — the
    /// clamps are boundaries, not a gain stage.
    func testTheClampsDoNotAlterAHealthyLevel() {
        let plain = voicing()
        plain.amplitude = 0.5
        let quiet = voicing()
        quiet.amplitude = 0.5
        quiet.patchOutputLevel = 0.5
        let full = peak(plain, blocks: 16)
        let halved = peak(quiet, blocks: 16)
        XCTAssertGreaterThan(full, 0, "baseline is silent — see testAHealthyVoiceMakesSound")
        XCTAssertEqual(halved / full, 0.5, accuracy: 0.05, """
        halving `patchOutputLevel` changed the peak by \(halved / full)×, not 0.5×. The trim \
        is supposed to pass through the smoother untouched; a bound that bites here is a \
        level change, not a guard.
        """)
    }

    /// Every `SynthPatch` compiled into the binary — same set and same reasoning as
    /// `FilterCutoffClampTests.shippedPatches`, including doorless `PatchLibrary`, because
    /// leaving a preset out is how one drifts toward a bound unseen. Saved `PatchStore`
    /// patches stay out of scope: they are not compiled in.
    private var shippedPatches: [(label: String, patch: SynthPatch)] {
        SynthPatch.factory.map { (label: "factory “\($0.name)”", patch: $0) }
        + MusicStyle.offered.map { (label: "genre “\($0.rawValue)”", patch: $0.synthPatch) }
        + PatchLibrary.all.map { (label: "library “\($0.patch.name)”", patch: $0.patch) }
    }
}
