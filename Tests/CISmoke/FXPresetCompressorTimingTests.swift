// FXPresetCompressorTimingTests.swift
// Echoel — the compressor's Attack/Release/Knee, in the BLOCKING bundle.
//
// FOUNDER, 2026-07-29: *"FX professionell vertiefen."* The compressor had Threshold, Ratio and
// Make-up — how MUCH is taken off — and no way at all to say how it MOVES. `attackMs`,
// `releaseMs` and `kneeDb` existed in `EchoelCompressor` with, in that file's own words,
// "nothing writes releaseMs or attackMs today". A compressor you cannot time is not a
// compressor you can mix with; on a bio-driven take that swells and settles it is the audible
// half of the processor.
//
// ⚠️ THE FAILURE THIS FILE EXISTS TO CATCH is not "the slider does nothing" — that is visible
// in ten seconds on a device. It is the SILENT one: a preset saved before these fields existed
// must load sounding EXACTLY as it did. Additive `Codable` gets that right only if the decode
// defaults equal the ENGINE's initial values; a default that merely looks tidy (0, or 1, or a
// round 50 ms) would re-voice every preset a user has already saved, with no error anywhere.
// That is the #163/#170 data-loss class wearing a different coat: nothing is lost, everything
// is quietly changed.

import Foundation
import XCTest
@testable import Echoelmusic

final class FXPresetCompressorTimingTests: XCTestCase {

    /// THE ONE THAT MATTERS. A payload from before #221 — no `compAttack`, no `compRelease`,
    /// no `compKnee` — must decode to the engine's own starting values, so the preset sounds
    /// unchanged. Written as raw JSON rather than by re-encoding a `FXPreset`, because
    /// re-encoding would include the new keys and the test would prove nothing.
    func testAPresetSavedBeforeTheseControlsExistedSoundsUnchanged() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Old","tags":[],"schema":3,
         "fxEnabled":true,
         "compressorEnabled":true,"compThreshold":-20,"compRatio":4,"compMakeup":2,
         "limiterEnabled":true,"limiterCeiling":-0.5}
        """
        let preset = try JSONDecoder().decode(FXPreset.self, from: Data(json.utf8))

        // The values it DID carry survive.
        XCTAssertEqual(preset.compThreshold, -20)
        XCTAssertEqual(preset.compRatio, 4)
        XCTAssertEqual(preset.compMakeup, 2)

        // …and the new ones land on the engine's defaults, not on tidy-looking numbers.
        let fresh = EchoelCompressor(sampleRate: 48000)
        XCTAssertEqual(preset.compAttack, fresh.attackMs,
                       "an old preset must attack exactly as it always did")
        XCTAssertEqual(preset.compRelease, fresh.releaseMs,
                       "an old preset must release exactly as it always did")
        XCTAssertEqual(preset.compKnee, fresh.kneeDb,
                       "an old preset must keep its knee")
    }

    /// The controls must survive a save/load round-trip. `CodingKeys` and `encode(to:)` here
    /// are SYNTHESIZED while `init(from:)` is hand-written as one `f(.key, default)` lookup
    /// per field — so the asymmetry this covers is a MIS-WIRED key, `compAttack = f(.compRelease, …)`,
    /// the copy-paste slip that fifty near-identical lines invite. Encoding still writes both
    /// keys, decoding silently crosses or drops them, and nothing anywhere raises.
    ///
    /// ⚠️ It does NOT catch "a property added to the struct but forgotten in the decoder" —
    /// an earlier version of this comment claimed that, and it is compiler-impossible: these
    /// three have no declaration-site default, so omitting them from `init(from:)` leaves
    /// `self` uninitialized and the file does not build. Worth stating, because a test whose
    /// advertised failure mode cannot occur reads as covering more than it does.
    func testTheTimingControlsSurviveASaveAndLoad() throws {
        var preset = FXPreset.capture(from: EchoelFXChain(sampleRate: 48000), fxEnabled: true, name: "Round")
        preset.compAttack = 3.5
        preset.compRelease = 450
        preset.compKnee = 12

        let back = try JSONDecoder().decode(
            FXPreset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(back.compAttack, 3.5)
        XCTAssertEqual(back.compRelease, 450)
        XCTAssertEqual(back.compKnee, 12)
    }

    /// Applying a preset must actually reach the DSP. Without this the row would set a stored
    /// property that nothing reads — a lying control, and this repo has an open task naming
    /// four of those.
    func testApplyingAPresetReachesTheCompressor() {
        let chain = EchoelFXChain(sampleRate: 48000)
        var preset = FXPreset.capture(from: chain, fxEnabled: true, name: "Applied")
        preset.compAttack = 0.7
        preset.compRelease = 900
        preset.compKnee = 0

        preset.apply(to: chain)
        XCTAssertEqual(chain.compressor.attackMs, 0.7)
        XCTAssertEqual(chain.compressor.releaseMs, 900)
        XCTAssertEqual(chain.compressor.kneeDb, 0)
    }

    /// …and capturing must read them BACK out, or "save" would quietly write the defaults over
    /// whatever the user dialled in. Capture and apply are two halves of one promise, and a
    /// test of only one half is the shape that lets the other rot.
    func testCapturingReadsTheTimingBackOutOfTheChain() {
        let chain = EchoelFXChain(sampleRate: 48000)
        chain.compressor.attackMs = 25
        chain.compressor.releaseMs = 300
        chain.compressor.kneeDb = 9

        let preset = FXPreset.capture(from: chain, fxEnabled: true, name: "Captured")
        XCTAssertEqual(preset.compAttack, 25)
        XCTAssertEqual(preset.compRelease, 300)
        XCTAssertEqual(preset.compKnee, 9)
    }

    /// THE SAFETY PROPERTY THE UI RANGE DOES NOT PROVIDE. `EchoelCompressor.coeff(forMs:)`
    /// clamps to 0.01…10 000 ms because past ~700 s `1 - expf(-1/t)` rounds to exactly 0 in
    /// Float, the coefficient dies, and the gain reduction can never move back toward 0 —
    /// permanent attenuation, the "fail to resting, never to silence" law. Until #221 nothing
    /// could write those fields, so the clamp guarded a hypothetical. It now guards a real
    /// path: a hand-edited or corrupted preset carries any Float straight into the engine.
    ///
    /// ⚠️ THE FIRST VERSION OF THIS TEST COULD NOT FAIL, and it is worth knowing exactly how,
    /// because it looked thorough. It set the absurd timing BEFORE processing anything: with
    /// `ms = .greatestFiniteMagnitude` the unclamped `t` overflows Float to `+inf`, so BOTH
    /// coefficients are 0 from the very first sample, `grState` never leaves 0, and the output
    /// is simply the input — green with the clamp deleted. A latch needs attenuation to exist
    /// FIRST and then be unable to leave. Its second assertion was unfailable too (`grState`
    /// is bounded, so a latched compressor still outputs ~0.002, never 0), and its "silence"
    /// was −26 dBFS against a −30 dB threshold — 4 dB ABOVE it, so the recovery phase it
    /// claimed to test was still the attack branch.
    ///
    /// This version builds real gain reduction with HEALTHY ballistics, then writes the absurd
    /// release, then feeds true silence and asserts the reduction actually returns.
    func testAnAbsurdReleaseCannotLatchTheCompressor() {
        let comp = EchoelCompressor(sampleRate: 48000)
        comp.thresholdDb = -30
        comp.ratio = 20
        comp.attackMs = 1                     // healthy, so reduction really accumulates

        for _ in 0..<4800 { _ = comp.processStereo(0.9, 0.9) }
        let reduced = comp.gainReductionDb
        XCTAssertLessThan(reduced, -6,
                          "the burst did not compress — the rest of this test would be vacuous")

        // NOW the corrupted value arrives, exactly as a hand-edited preset would deliver it.
        comp.releaseMs = .greatestFiniteMagnitude

        // True silence: unambiguously below the threshold and below the knee, so the release
        // branch is the only one that can run.
        var out: Float = 1
        for _ in 0..<96_000 { out = comp.processStereo(0, 0).0 }

        XCTAssertTrue(out.isFinite, "an absurd timing must not produce non-finite audio")
        XCTAssertGreaterThan(comp.gainReductionDb, reduced + 1,
                             "the gain reduction never moved back toward 0 — the latched, "
                             + "permanently-attenuating state the ms clamp exists to prevent")
    }

    /// The LIMITER deliberately did NOT get these controls, and that is a decision rather than
    /// an oversight. ⛔ TWO WRONG REASONS STOOD HERE before the measured one — first "a slowed
    /// attack would let material overshoot the ceiling", then "it would alias instead". Both
    /// false. `attackMs` had NO EFFECT on the output at all on the finite path: the attack
    /// branch is only entered when `env` rose to `peak`, and on exactly those samples the
    /// absolute guard `if peak * g > ceilingLin { g = target }` overwrites the ballistics.
    /// Simulated over four signal classes and six orders of magnitude, the attack-branch count
    /// EQUALS the guard-fire count every time and the output is bit-identical.
    ///
    /// ⛔ THIS TEST USED TO SET `limiter.attackMs` — it cannot any more, and that IS #231's
    /// fix: the property is a `private static let` since the measurement proved a settable one
    /// would be a LYING CONTROL (#164, #227). Removing the setter is a stronger guarantee than
    /// any assertion about it could be, so what is pinned here now is the half that survives
    /// and is still settable: the limiter's RELEASE is real (it moves recovery time, #199) and
    /// must still not cross a preset boundary.
    func testTheLimiterTimingIsStillNotAPresetField() {
        let source = EchoelFXChain(sampleRate: 48000)
        source.limiter.releaseMs = 400        // absurd for a brick wall
        let preset = FXPreset.capture(from: source, fxEnabled: true, name: "Limiter")

        let target = EchoelFXChain(sampleRate: 48000)
        preset.apply(to: target)

        // Asserted as a TRANSFER that does not happen, not merely as a default that is still
        // the default — the second version would pass even if the preset did carry the field.
        XCTAssertNotEqual(target.limiter.releaseMs, 400,
                          "the limiter's release crossed a preset boundary; it must not")
        XCTAssertEqual(target.limiter.releaseMs, EchoelLimiter(sampleRate: 48000).releaseMs)
    }

    /// #231 turned `attackCoeff` into a `let` and took it OUT of `recalc()`. That is safe only
    /// because `recalc()`'s remaining job — rewriting `ceilingLin` — still happens on a
    /// `ceilingDb` write. If a future edit drops or reorders that, the limiter would keep
    /// clamping to the OLD ceiling and nothing else in this suite would notice.
    ///
    /// ⛔ THIS TEST PINS THE CEILING REFRESH AND NOTHING ELSE. Its first version also claimed
    /// to pin the attack BRANCH; the DSP review disproved that by simulation — with a DC
    /// input `env == peak` on 100% of samples, which is exactly the condition under which the
    /// absolute guard is guaranteed to preempt the ballistics. It passed bit-identically with
    /// the attack branch DELETED. The branch now has its own test below, on a stimulus where
    /// the branch can actually escape. Two other claims went with it: "drive it into limiting"
    /// was false (0.9 < the default ceiling 0.966, so the guard fires zero times and `gain`
    /// stays exactly 1.0 through the pre-roll), and the pre-roll only charges `env`.
    func testLoweringTheCeilingMidStreamStillReachesTheNewCeiling() {
        let lim = EchoelLimiter(sampleRate: 48000)
        // Charge the detector to 0.9. NOT limiting: 0.9 < the default ceiling (0.966).
        for _ in 0..<4800 { _ = lim.processStereo(0.9, 0.9) }

        lim.ceilingDb = -12
        var peak: Float = 0
        for _ in 0..<4800 {
            let (l, r) = lim.processStereo(0.9, 0.9)
            peak = Swift.max(peak, Swift.max(abs(l), abs(r)))
        }

        let ceiling = powf(10, -12.0 / 20.0)
        XCTAssertLessThanOrEqual(peak, ceiling * 1.001,
                                 "a mid-stream ceilingDb write did not reach the audio — "
                                 + "recalc() no longer refreshes ceilingLin")
        // Non-vacuity: the new ceiling really is below what the old one passed, so the
        // assertion above could fail. Without this a broken limiter outputting silence
        // would also "pass". Simulated settled peak = 0.2511886, i.e. exactly the ceiling.
        XCTAssertGreaterThan(peak, ceiling * 0.5,
                             "the limiter went (near-)silent instead of settling at the ceiling")
    }

    /// THE ATTACK BALLISTICS IS LIVE ON EXACTLY ONE PATH, and this is it.
    ///
    /// With the ceiling CONSTANT the attack branch is entered only when `env` rose, and the
    /// detector's rise is instantaneous, so `env == peak` there and the absolute guard
    /// overwrites `g` every time. A `ceilingDb` write breaks that: it drops `target` WITHOUT
    /// touching `env`. If the detector is then holding a decaying peak ABOVE the current
    /// sample — 88.5% of samples on a sine, so the normal case, not a corner — `peak * g`
    /// stays under the ceiling, the guard does not fire, and `attackCoeff` reaches the audio.
    ///
    /// Stimulus: 200 Hz at 48 kHz is exactly 240 samples per cycle, so sample 4800 is a zero
    /// crossing by construction — `peak ≈ 0` while `env ≈ 0.873`. Simulated gain reduction one
    /// sample after the write (bit-faithful Float32 replica of `processStereo`):
    ///
    ///     attack 0.5 ms (shipped)      −0.2562 dB
    ///     attack branch DELETED        −0.0021 dB
    ///     attack 0.01 ms               −8.4830 dB
    ///     instant jump to target      ≈−10.8   dB
    ///
    /// The band below admits only the first. That is the point: the previous version of this
    /// pin passed with the branch deleted, which is the opposite of a guard.
    func testTheAttackBallisticsRideAMidStreamCeilingDrop() {
        let sr: Float = 48000
        let lim = EchoelLimiter(sampleRate: sr)
        let w = 2 * Float.pi * 200 / sr
        for i in 0..<4800 {
            let s = 0.9 * sinf(w * Float(i))
            _ = lim.processStereo(s, s)
        }
        XCTAssertEqual(lim.gainReductionDb, 0, accuracy: 1e-6,
                       "precondition: 0.9 is under the default ceiling, so nothing limited yet")

        lim.ceilingDb = -12
        _ = lim.processStereo(0.9 * sinf(w * 4800), 0.9 * sinf(w * 4800))
        let gr = lim.gainReductionDb

        XCTAssertLessThan(gr, -0.10,
                          "the gain barely moved (\(gr) dB) — the attack branch is gone and "
                          + "the release coefficient is doing the work")
        XCTAssertGreaterThan(gr, -1.0,
                             "the gain jumped (\(gr) dB) far past one attack step — either the "
                             + "coefficient changed or the guard is clamping a sample it must "
                             + "not, at a zero crossing")
    }
}
