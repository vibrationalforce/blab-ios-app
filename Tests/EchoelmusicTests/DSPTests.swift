#if canImport(AVFoundation)
// DSPTests.swift
// Echoelmusic — Phase 2 Test Coverage: DSP Engine Tests
//
// Tests for EchoelDDSP + EchoelPolyDDSP render/bio-reactive paths and crash-hardening.
// (Analog-emulation + CrossfadeCurve/CrossfadeRegion suites removed 2026-07-21 —
//  those subsystems no longer exist in Sources.)

import XCTest
@testable import Echoelmusic

// MARK: - EchoelDDSP Tests

final class EchoelDDSPTests: XCTestCase {

    func testInitialization() {
        let ddsp = EchoelDDSP(harmonicCount: 32, noiseBandCount: 33, sampleRate: 48000, frameSize: 256)
        XCTAssertEqual(ddsp.harmonicCount, 32)
        XCTAssertEqual(ddsp.noiseBandCount, 33)
        XCTAssertEqual(ddsp.sampleRate, 48000)
        XCTAssertEqual(ddsp.frameSize, 256)
    }

    func testDefaultParameters() {
        let ddsp = EchoelDDSP()
        XCTAssertEqual(ddsp.harmonicCount, 64)
        XCTAssertEqual(ddsp.frequency, 110.0)                       // A2 — deep, warm base
        XCTAssertEqual(ddsp.harmonicLevel, 0.8, accuracy: 0.01)
        XCTAssertEqual(ddsp.harmonicity, 0.88, accuracy: 0.01)      // clean pad — mostly harmonic
        XCTAssertEqual(ddsp.noiseLevel, 0.01, accuracy: 0.01)       // minimal noise — clean
        XCTAssertEqual(ddsp.amplitude, 0.5, accuracy: 0.01)         // moderate — room for modulation
    }

    func testHarmonicAmplitudesCount() {
        let ddsp = EchoelDDSP(harmonicCount: 16)
        XCTAssertEqual(ddsp.harmonicAmplitudes.count, 16)
    }

    func testNoiseMagnitudesCount() {
        let ddsp = EchoelDDSP(noiseBandCount: 33)
        XCTAssertEqual(ddsp.noiseMagnitudes.count, 33)
    }

    func testNoiseColorCases() {
        let cases = EchoelDDSP.NoiseColor.allCases
        XCTAssertEqual(cases.count, 5)
        XCTAssertTrue(cases.contains(.white))
        XCTAssertTrue(cases.contains(.pink))
        XCTAssertTrue(cases.contains(.brown))
        XCTAssertTrue(cases.contains(.blue))
        XCTAssertTrue(cases.contains(.violet))
    }

    func testSpectralShapeCases() {
        let cases = EchoelDDSP.SpectralShape.allCases
        XCTAssertEqual(cases.count, 8)
        XCTAssertTrue(cases.contains(.natural))
        XCTAssertTrue(cases.contains(.bright))
        XCTAssertTrue(cases.contains(.dark))
        XCTAssertTrue(cases.contains(.formant))
        XCTAssertTrue(cases.contains(.metallic))
        XCTAssertTrue(cases.contains(.hollow))
        XCTAssertTrue(cases.contains(.bell))
        XCTAssertTrue(cases.contains(.flat))
    }

    func testEnvelopeCurveCases() {
        let cases = EchoelDDSP.EnvelopeCurve.allCases
        XCTAssertEqual(cases.count, 3)
        XCTAssertTrue(cases.contains(.linear))
        XCTAssertTrue(cases.contains(.exponential))
        XCTAssertTrue(cases.contains(.logarithmic))
    }

    func testFrequencyRange() {
        let ddsp = EchoelDDSP()
        ddsp.frequency = 440.0
        XCTAssertEqual(ddsp.frequency, 440.0)

        ddsp.frequency = 20.0
        XCTAssertEqual(ddsp.frequency, 20.0)

        ddsp.frequency = 20000.0
        XCTAssertEqual(ddsp.frequency, 20000.0)
    }

    func testADSRParameters() {
        let ddsp = EchoelDDSP()
        ddsp.attack = 0.05
        ddsp.decay = 0.2
        ddsp.sustain = 0.6
        ddsp.release = 0.5

        XCTAssertEqual(ddsp.attack, 0.05, accuracy: 0.001)
        XCTAssertEqual(ddsp.decay, 0.2, accuracy: 0.001)
        XCTAssertEqual(ddsp.sustain, 0.6, accuracy: 0.001)
        XCTAssertEqual(ddsp.release, 0.5, accuracy: 0.001)
    }

    func testVibratoParameters() {
        let ddsp = EchoelDDSP()
        ddsp.vibratoRate = 5.5
        ddsp.vibratoDepth = 0.3

        XCTAssertEqual(ddsp.vibratoRate, 5.5, accuracy: 0.01)
        XCTAssertEqual(ddsp.vibratoDepth, 0.3, accuracy: 0.01)
    }

    func testSpectralMorphing() {
        let ddsp = EchoelDDSP()
        XCTAssertNil(ddsp.morphTarget)
        XCTAssertEqual(ddsp.morphPosition, 0)

        ddsp.morphTarget = .metallic
        ddsp.morphPosition = 0.5
        XCTAssertEqual(ddsp.morphTarget, .metallic)
        XCTAssertEqual(ddsp.morphPosition, 0.5, accuracy: 0.01)
    }

    func testTimbreTransfer() {
        let ddsp = EchoelDDSP()
        XCTAssertNil(ddsp.timbreProfile)
        XCTAssertEqual(ddsp.timbreBlend, 0)

        let profile: [Float] = Array(repeating: 0.5, count: 64)
        ddsp.timbreProfile = profile
        ddsp.timbreBlend = 0.7
        XCTAssertNotNil(ddsp.timbreProfile)
        XCTAssertEqual(ddsp.timbreBlend, 0.7, accuracy: 0.01)
    }

    func testReverbParameters() {
        let ddsp = EchoelDDSP()
        XCTAssertEqual(ddsp.reverbMix, 0.25, accuracy: 0.001)   // moderate reverb default
        ddsp.reverbMix = 0.4
        ddsp.reverbDecay = 2.5
        XCTAssertEqual(ddsp.reverbMix, 0.4, accuracy: 0.01)
        XCTAssertEqual(ddsp.reverbDecay, 2.5, accuracy: 0.01)
    }
}

// MARK: - EchoelDDSP Render Tests

final class EchoelDDSPRenderTests: XCTestCase {

    func testRenderProducesOutput() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.noteOn(frequency: 440)
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        let hasNonZero = buffer.contains { $0 != 0 }
        XCTAssertTrue(hasNonZero, "DDSP should produce non-zero output after noteOn")
    }

    func testRenderNaNGuard() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.noteOn(frequency: 440)
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "DDSP render must not produce NaN")
            XCTAssertFalse(sample.isInfinite, "DDSP render must not produce Inf")
        }
    }

    func testRenderStereo() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 128)
        ddsp.noteOn(frequency: 440)
        var buffer = [Float](repeating: 0, count: 256) // 128 frames * 2 channels
        ddsp.render(buffer: &buffer, frameCount: 128, stereo: true)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN)
            XCTAssertFalse(sample.isInfinite)
        }
    }

    func testRenderZeroFrameCount() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.noteOn(frequency: 440)
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 0)
        // Buffer should remain all zeros
        for sample in buffer {
            XCTAssertEqual(sample, 0)
        }
    }

    func testRenderExtremeFrequency() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.noteOn(frequency: 22000) // Near Nyquist
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "High frequency must not produce NaN")
            XCTAssertFalse(sample.isInfinite, "High frequency must not produce Inf")
        }
    }

    func testRenderSilenceBeforeNoteOn() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertEqual(sample, 0, accuracy: 0.001, "Should be silent before noteOn")
        }
    }

    func testAllSpectralShapesRender() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 128)
        for shape in EchoelDDSP.SpectralShape.allCases {
            ddsp.spectralShape = shape
            ddsp.noteOn(frequency: 440)
            var buffer = [Float](repeating: 0, count: 128)
            ddsp.render(buffer: &buffer, frameCount: 128)
            for sample in buffer {
                XCTAssertFalse(sample.isNaN, "NaN with shape \(shape)")
                XCTAssertFalse(sample.isInfinite, "Inf with shape \(shape)")
            }
        }
    }
}

// MARK: - EchoelPolyDDSP Render Tests

final class EchoelPolyDDSPRenderTests: XCTestCase {

    func testRenderStereoOutput() {
        let poly = EchoelPolyDDSP(maxVoices: 4, sampleRate: 48000)
        poly.noteOn(note: 60, velocity: 0.8)
        var left = [Float](repeating: 0, count: 256)
        var right = [Float](repeating: 0, count: 256)
        poly.renderStereo(left: &left, right: &right, frameCount: 256)
        let hasOutput = left.contains { $0 != 0 } || right.contains { $0 != 0 }
        XCTAssertTrue(hasOutput, "PolyDDSP should produce output after noteOn")
    }

    func testRenderNaNGuard() {
        let poly = EchoelPolyDDSP(maxVoices: 4, sampleRate: 48000)
        poly.noteOn(note: 60, velocity: 0.8)
        var left = [Float](repeating: 0, count: 256)
        var right = [Float](repeating: 0, count: 256)
        poly.renderStereo(left: &left, right: &right, frameCount: 256)
        for i in 0..<256 {
            XCTAssertFalse(left[i].isNaN, "Left NaN at \(i)")
            XCTAssertFalse(right[i].isNaN, "Right NaN at \(i)")
            XCTAssertFalse(left[i].isInfinite, "Left Inf at \(i)")
            XCTAssertFalse(right[i].isInfinite, "Right Inf at \(i)")
        }
    }

    func testVoiceStealing() {
        let poly = EchoelPolyDDSP(maxVoices: 2, sampleRate: 48000, frameSize: 128)
        // Exceed max voices
        poly.noteOn(note: 60, velocity: 0.8)
        poly.noteOn(note: 64, velocity: 0.8)
        poly.noteOn(note: 67, velocity: 0.8) // Should steal a voice
        XCTAssertLessThanOrEqual(poly.activeVoiceCount, 2, "Should not exceed maxVoices")
        var left = [Float](repeating: 0, count: 128)
        var right = [Float](repeating: 0, count: 128)
        poly.renderStereo(left: &left, right: &right, frameCount: 128)
        for i in 0..<128 {
            XCTAssertFalse(left[i].isNaN, "Voice stealing must not produce NaN")
        }
    }

    func testAllNotesOff() {
        let poly = EchoelPolyDDSP(maxVoices: 4, sampleRate: 48000, frameSize: 128)
        poly.noteOn(note: 60, velocity: 0.8)
        poly.noteOn(note: 64, velocity: 0.8)
        poly.allNotesOff()
        XCTAssertEqual(poly.activeVoiceCount, 0, "All voices should be off")
    }

    func testUnisonOffSpawnsOneVoice() {
        let poly = EchoelPolyDDSP(maxVoices: 6, sampleRate: 48000, frameSize: 128)
        poly.setUnison(count: 1, detuneCents: 12)   // count 1 = off regardless of detune
        poly.noteOn(note: 60, velocity: 0.8)
        XCTAssertEqual(poly.activeVoiceCount, 1, "Unison off → one voice per note")
    }

    func testUnisonStacksDetunedVoices() {
        let poly = EchoelPolyDDSP(maxVoices: 6, sampleRate: 48000, frameSize: 128)
        poly.setUnison(count: 3, detuneCents: 14)
        poly.noteOn(note: 60, velocity: 0.8)
        XCTAssertEqual(poly.activeVoiceCount, 3, "Unison 3 → three voices for one note")
        // A single noteOff releases the whole stack (they share the note tag).
        poly.noteOff(note: 60)
        XCTAssertEqual(poly.activeVoiceCount, 0, "noteOff releases the entire unison stack")
    }

    func testUnisonClampedToMax() {
        let poly = EchoelPolyDDSP(maxVoices: 8, sampleRate: 48000, frameSize: 128)
        poly.setUnison(count: 99, detuneCents: 999)
        poly.noteOn(note: 60, velocity: 0.8)
        XCTAssertEqual(poly.activeVoiceCount, EchoelPolyDDSP.maxUnison,
                       "Unison count clamps to maxUnison")
    }

    func testUnisonRenderIsFinite() {
        let poly = EchoelPolyDDSP(maxVoices: 6, sampleRate: 48000, frameSize: 128)
        poly.setUnison(count: 3, detuneCents: 20)
        poly.noteOn(note: 57, velocity: 1.0)
        var left = [Float](repeating: 0, count: 128)
        var right = [Float](repeating: 0, count: 128)
        poly.renderStereo(left: &left, right: &right, frameCount: 128)
        for i in 0..<128 {
            XCTAssertTrue(left[i].isFinite && right[i].isFinite, "Unison render finite at \(i)")
        }
    }
}

// MARK: - Velocity survives the bio pulse (#174 / #177)
//
// THE DEFECT THESE PIN. `spawnVoice` sets `amplitude` from the played velocity, and then
// `applyBioToVoice` OVERWRITES `amplitude` outright (`ampBase = 0.35 + coherence * 0.15`),
// re-applied on every 10 Hz bio frame. With `bioModulationEnabled` — i.e. whenever the
// instrument is doing the one thing it exists to do — the played velocity therefore has no
// effect on loudness at all.
//
// Why that is not a cosmetic complaint: the Mix faders (bass/pad/lead) are applied by baking
// `velocity * fader` into the generated notes at compose time. So a fader pulled to 0 makes a
// note that is STRUCTURALLY silent (velocity 0) but AUDIBLY unchanged (bio overwrites it) —
// the mute does not mute. Meanwhile the visual reads note amplitude out of `MusicalFrame` and
// correctly sees zero, which is exactly the founder's build-2466 log: `mfNotes=5 level=0.00`
// while music is playing. One number, two consumers, opposite answers.
//
// The names carry the diagnosis on purpose: CI reports failing test NAMES only, never
// assertion messages, so each name states the single fact its one assertion establishes.
final class EchoelPolyDDSPVelocityUnderBioTests: XCTestCase {

    /// Peak absolute sample over `blocks` render blocks. 400 × 128 = 51 200 samples ≈ 1.07 s at
    /// 48 kHz, i.e. more than twice the 0.5 s default attack — the first draft used 200 blocks,
    /// which cleared that attack by only 6.7 % and would have turned into a "not started yet"
    /// comparison the moment anyone raised the default or applied a pad patch here.
    private func peak(_ poly: EchoelPolyDDSP, blocks: Int = 400, frames: Int = 128) -> Float {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        var p: Float = 0
        for _ in 0..<blocks {
            poly.renderStereo(left: &left, right: &right, frameCount: frames)
            for i in 0..<frames { p = Swift.max(p, Swift.max(abs(left[i]), abs(right[i]))) }
        }
        return p
    }

    /// Arm the engine the way the app does: bio modulation on, one bio frame already applied,
    /// so `spawnVoice`'s `applyBioToVoice` runs for the note we are about to play.
    private func bioArmedEngine() -> EchoelPolyDDSP {
        let poly = EchoelPolyDDSP(maxVoices: 4, sampleRate: 48000, frameSize: 128)
        poly.bioModulationEnabled = true
        poly.applyBioReactive(coherence: 0.7, hrvVariability: 0.5, heartRate: 0.5,
                              breathPhase: 0.5, breathDepth: 0.5, lfHfRatio: 0.5)
        return poly
    }

    /// THE MUTE. A Mix fader at 0 bakes velocity 0 into the note; that note must be silent.
    func testBio_velocityZeroIsSilent_soAMixFaderAtZeroActuallyMutes() {
        let poly = bioArmedEngine()
        poly.noteOn(note: 60, velocity: 0)
        // A second bio frame, as the 10 Hz poll delivers while the note rings.
        poly.applyBioReactive(coherence: 0.7)
        XCTAssertLessThan(peak(poly), 1e-4,
                          "velocity 0 must render silence even while bio modulation is running")
    }

    /// THE DYNAMICS. Under bio, a harder note must still be louder than a soft one — this is
    /// what makes the Mix faders audible at all, not just visible.
    func testBio_harderVelocityIsLouderThanSoft_soTheMixFadersAreAudible() {
        let soft = bioArmedEngine()
        soft.noteOn(note: 60, velocity: 0.2)
        soft.applyBioReactive(coherence: 0.7)
        let softPeak = peak(soft)

        let hard = bioArmedEngine()
        hard.noteOn(note: 60, velocity: 1.0)
        hard.applyBioReactive(coherence: 0.7)
        let hardPeak = peak(hard)

        XCTAssertGreaterThan(hardPeak, softPeak * 1.5,
                             "under bio, velocity 1.0 must be clearly louder than velocity 0.2")
    }

    /// NEGATIVE CONTROL — with bio OFF this already worked, and must keep working. If this one
    /// ever goes red alongside the two above, the fault is in the velocity path itself, not in
    /// the bio overwrite.
    func testNoBio_harderVelocityIsLouderThanSoft() {
        let soft = EchoelPolyDDSP(maxVoices: 4, sampleRate: 48000, frameSize: 128)
        soft.noteOn(note: 60, velocity: 0.2)
        let hard = EchoelPolyDDSP(maxVoices: 4, sampleRate: 48000, frameSize: 128)
        hard.noteOn(note: 60, velocity: 1.0)
        XCTAssertGreaterThan(peak(hard), peak(soft) * 1.5,
                             "without bio, velocity already sets level — this is the control")
    }

    /// THE LEVEL. A NOMINAL note must keep the level it had before this change, or the founder
    /// hears "leiser geworden" and the fix reads as a regression. `velocityGain` is a ratio
    /// against `EchoelDDSP.nominalVelocity`, so a note played AT that velocity must render
    /// within a hair of the old bio-only amplitude (0.456 at coherence 0.7). The first draft
    /// multiplied by the raw velocity instead, which cost the pad ~7 dB — this is the test that
    /// would have caught it.
    /// A LEVEL PIN, not a defect pin — and labelled that way on purpose. It is green before AND
    /// after this change, because the whole point is that the level must not move. Its job is to
    /// stop a future edit from silently dropping the instrument's loudness, which is the failure
    /// mode a founder reports as "leiser geworden" and nobody can bisect from a test suite.
    ///
    /// Scope, stated so it is not over-trusted: it covers the two writers of voice `amplitude`
    /// (`spawnVoice` and the bio apply) and NOTHING downstream. A regression in
    /// `patchOutputLevel`, the poly makeup gain or the safety tanh passes this test unnoticed.
    ///
    /// It asserts the ABSOLUTE amplitude, not a ratio. An earlier draft compared a nominal note
    /// against the hottest one; that cannot catch a uniform drop at all — halve every level and
    /// the ratio is unchanged. The old number is not guesswork: bio amplitude at coherence 0.7 is
    /// `0.35 + 0.7 * 0.15 = 0.455`, the breath swell is exactly 1.0 at the default phase 0.5, and
    /// a nominal-velocity note carries `velocityGain` 1.0 by construction (the unity fixpoint).
    func testBio_aNominalVelocityNoteKeepsItsPreviousAbsoluteLevel() {
        let poly = bioArmedEngine()
        poly.noteOn(note: 60, velocity: EchoelDDSP.nominalVelocity)
        poly.applyBioReactive(coherence: 0.7)

        // Read the voice's target amplitude directly: no render, so the envelope stage cannot
        // colour the reading and the assertion is about LEVEL, not about attack timing.
        var amplitudes: [Float] = []
        poly.forEachVoice { if $0.isActive { amplitudes.append($0.amplitude) } }
        XCTAssertEqual(amplitudes.count, 1, "one note, unison off ⇒ exactly one active voice")
        XCTAssertEqual(amplitudes.first ?? 0, 0.455, accuracy: 0.04,
                       "a nominal-velocity note must still sit at the pre-#174 bio amplitude")
    }

    /// THE UNITY FIXPOINT, asserted through the real `spawnVoice` path across the range of patch
    /// attacks the genre roster actually uses (0.005 s pluck … 0.5 s pad). A nominal note must
    /// come out at gain exactly 1 for EVERY exponent — that is what lets a pluck patch and a pad
    /// patch both keep their level, and it is why the gamma sits on the exponent rather than on
    /// the result.
    ///
    /// The first draft of this test computed `pow(nominal / nominal, …)` inline. That reduces to
    /// `pow(1, x)`, which is 1 by definition for ANY value of either constant — so deleting the
    /// `/ nominalVelocity` from the production line, i.e. exactly the ~7 dB regression this whole
    /// design exists to prevent, would have left it green. A test that cannot fail is worse than
    /// no test, because it gets cited as coverage.
    func testVelocityGain_isExactlyUnityAtNominalVelocity_forEveryPatchAttack() {
        for attack in [Float(0.005), 0.05, 0.15, 0.5] {
            let poly = EchoelPolyDDSP(maxVoices: 2, sampleRate: 48000, frameSize: 128)
            poly.forEachVoice { $0.attack = attack }
            poly.noteOn(note: 60, velocity: EchoelDDSP.nominalVelocity)
            var gains: [Float] = []
            poly.forEachVoice { if $0.isActive { gains.append($0.velocityGain) } }
            XCTAssertEqual(gains.first ?? 0, 1.0, accuracy: 1e-5,
                           "nominal velocity must give gain 1 at patch attack \(attack)")
        }
    }

    /// THE MUTE, at the gain level rather than the render level — the tripwire for a
    /// `velocityCurve` of 0. `pow(x, 0)` is 1 in C for every x INCLUDING 0, so setting that
    /// constant to zero (which an earlier doc comment wrongly offered as "velocity does nothing")
    /// would hand every note gain 1 and silently re-arm the un-muteable fader of #174.
    func testVelocityGain_isExactlyZeroAtVelocityZero_soTheCurveCannotUndoAMute() {
        let poly = EchoelPolyDDSP(maxVoices: 2, sampleRate: 48000, frameSize: 128)
        poly.noteOn(note: 60, velocity: 0)
        var gains: [Float] = []
        poly.forEachVoice { if $0.isActive { gains.append($0.velocityGain) } }
        XCTAssertEqual(gains.count, 1, "a muted note still occupies a voice — it is silent, not absent")
        XCTAssertEqual(gains.first ?? -1, 0, accuracy: 0,
                       "velocity 0 must give gain 0 EXACTLY, whatever the curve")
    }

    /// THE MAKEUP GAIN. Muting one role must not make the others quieter. The poly stage backs
    /// off by 1/√N over SOUNDING voices; a note at velocity 0 renders exact zeros, so counting
    /// it would mean pulling the Lead fader down also thins the pad. Two audible notes must
    /// render the same whether or not a third, muted note is held alongside them.
    func testBio_aMutedVoiceDoesNotPullDownTheVoicesThatAreStillAudible() {
        let alone = bioArmedEngine()
        alone.noteOn(note: 60, velocity: 0.5)
        alone.noteOn(note: 64, velocity: 0.5)
        alone.applyBioReactive(coherence: 0.7)
        let alonePeak = peak(alone)

        let withMuted = bioArmedEngine()
        withMuted.noteOn(note: 60, velocity: 0.5)
        withMuted.noteOn(note: 64, velocity: 0.5)
        withMuted.noteOn(note: 67, velocity: 0)      // the muted role
        withMuted.applyBioReactive(coherence: 0.7)
        let withMutedPeak = peak(withMuted)

        // Absolute, not a percentage: the two renders are deterministically identical (same
        // slots, same makeup trajectory, the muted voice contributes exact zeros), so any real
        // difference is a partial-count regression. A 2 % window would have hidden one.
        XCTAssertEqual(withMutedPeak, alonePeak, accuracy: 1e-5,
                       "a silent voice must not count toward the 1/sqrt(N) makeup backoff")
    }

    /// The MONO bio voice never sets a velocity (`noteVelocity` defaults to 0, documented as
    /// "no velocity context"). It must therefore be UNAFFECTED by the fix — a voice with no
    /// velocity context keeps the full bio-driven amplitude, or the whole bio-reactive synth
    /// goes silent. This is the test that stops the fix from being "multiply by velocity" naive.
    func testBioVoiceWithoutVelocityContextStaysAudible() {
        let voice = EchoelDDSP(sampleRate: 48000)
        voice.applyBioReactive(coherence: 0.7)
        XCTAssertGreaterThan(voice.amplitude, 0.1,
                             "a voice that was never given a velocity must keep the bio amplitude")
    }
}
// MARK: - DSP Crash Hardening Tests

final class DSPCrashHardeningTests: XCTestCase {

    // MARK: - EchoelDDSP Edge Cases

    func testDDSP_ZeroFrequency() {
        let ddsp = EchoelDDSP()
        ddsp.frequency = 0.0
        // Should not crash or produce NaN
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "Zero frequency should not produce NaN")
            XCTAssertFalse(sample.isInfinite, "Zero frequency should not produce Inf")
        }
    }

    func testDDSP_ExtremeFrequency() {
        let ddsp = EchoelDDSP()
        ddsp.frequency = 22050.0 // Nyquist
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "Nyquist frequency should not produce NaN")
        }
    }

    func testDDSP_ZeroAmplitude() {
        let ddsp = EchoelDDSP()
        ddsp.amplitude = 0.0
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        // All samples should be zero or near-zero
        let maxAbs = buffer.map { abs($0) }.max() ?? 0
        XCTAssertLessThan(maxAbs, 0.001, "Zero amplitude should produce silence")
    }

    func testDDSP_ZeroFrameCount() {
        let ddsp = EchoelDDSP()
        var buffer = [Float](repeating: 0, count: 0)
        // Must not crash or grow the buffer with an empty render.
        ddsp.render(buffer: &buffer, frameCount: 0)
        XCTAssertEqual(buffer.count, 0, "empty render must leave the buffer empty")
    }

    func testDDSP_SingleFrame() {
        let ddsp = EchoelDDSP()
        var buffer = [Float](repeating: 0, count: 1)
        ddsp.render(buffer: &buffer, frameCount: 1)
        XCTAssertFalse(buffer[0].isNaN, "Single frame should not produce NaN")
    }

    func testDDSP_BioReactiveWithZeroCoherence() {
        let ddsp = EchoelDDSP()
        ddsp.applyBioReactive(coherence: 0.0, hrvVariability: 0.0, heartRate: 0.0, breathPhase: 0.0, breathDepth: 0.0)
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "Zero bio values should not produce NaN")
        }
    }

    func testDDSP_BioReactiveWithExtremeValues() {
        let ddsp = EchoelDDSP()
        ddsp.applyBioReactive(coherence: 1.0, hrvVariability: 1.0, heartRate: 200.0, breathPhase: 1.0, breathDepth: 1.0)
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "Extreme bio values should not produce NaN")
            XCTAssertFalse(sample.isInfinite, "Extreme bio values should not produce Inf")
        }
    }
}
#endif
