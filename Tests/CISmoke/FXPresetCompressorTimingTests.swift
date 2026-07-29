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

    /// The controls must survive a save/load round-trip. Trivial-looking and not trivial: the
    /// `CodingKeys` here are SYNTHESIZED while `init(from:)` is hand-written, so a property
    /// added to the struct but forgotten in the decoder encodes fine and silently decodes to
    /// a default forever. That asymmetry is exactly what this catches.
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
    /// clamps to 0.01…10 000 ms because past ~700 s the coefficient rounds to exactly 0 in
    /// Float and the gain reduction can never return to 0 — permanent attenuation, the
    /// "fail to resting, never to silence" law. Until #221 nothing could write those fields,
    /// so the clamp guarded a hypothetical. It now guards a real path: a hand-edited or
    /// corrupted preset carries any Float straight into the engine.
    ///
    /// Asserted through BEHAVIOUR rather than the private coefficient: after an absurd
    /// release, the compressor must still produce finite audio and still recover.
    func testAnAbsurdPresetCannotLatchTheCompressor() {
        let chain = EchoelFXChain(sampleRate: 48000)
        chain.compressorEnabled = true
        chain.compressor.thresholdDb = -30
        chain.compressor.ratio = 20
        chain.compressor.attackMs = .greatestFiniteMagnitude
        chain.compressor.releaseMs = .greatestFiniteMagnitude

        // A loud burst to drive gain reduction, then silence to see it come back.
        for _ in 0..<4800 { _ = chain.compressor.processStereo(0.9, 0.9) }
        var last: Float = 0
        for _ in 0..<48_000 { last = chain.compressor.processStereo(0.05, 0.05).0 }

        XCTAssertTrue(last.isFinite, "an absurd timing must not produce non-finite audio")
        XCTAssertGreaterThan(abs(last), 0,
                             "the compressor latched at full attenuation — the permanent-"
                             + "silence failure the ms clamp exists to prevent")
    }

    /// The LIMITER deliberately did NOT get these controls, and that is a decision rather than
    /// an oversight: it is the last stage and a brick wall holding the true-peak ceiling, so a
    /// user-slowed attack would let material overshoot the very thing it exists to guarantee.
    /// Pinned so "finish the job" later is a deliberate act with a red test, not a tidy-up.
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
