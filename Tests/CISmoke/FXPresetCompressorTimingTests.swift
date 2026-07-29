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
    /// an oversight. ⛔ THE REASON GIVEN HERE WAS WRONG and is corrected in place: it said a
    /// user-slowed attack "would let material overshoot the ceiling". It would not —
    /// `EchoelDynamics.swift`'s `if peak * g > ceilingLin { g = target }` is an unconditional
    /// per-sample guard, so the ceiling holds at any attack. What a slowed attack costs is
    /// waveform SHAPE: the guard then engages on most samples, which is algebraically the
    /// zero-attack hard clipper #199 removed after the founder's "Es knistert". Aliasing, not
    /// overshoot. Pinned so "finish the job" later is a deliberate act with a red test.
    func testTheLimiterTimingIsStillNotAPresetField() {
        let source = EchoelFXChain(sampleRate: 48000)
        source.limiter.attackMs = 40          // absurd for a brick wall
        let preset = FXPreset.capture(from: source, fxEnabled: true, name: "Limiter")

        let target = EchoelFXChain(sampleRate: 48000)
        preset.apply(to: target)

        // Asserted as a TRANSFER that does not happen, not merely as a default that is still
        // the default — the second version would pass even if the preset did carry the field.
        XCTAssertNotEqual(target.limiter.attackMs, 40,
                          "the limiter's attack crossed a preset boundary; it must not")
        XCTAssertEqual(target.limiter.attackMs, EchoelLimiter(sampleRate: 48000).attackMs)
    }
}
