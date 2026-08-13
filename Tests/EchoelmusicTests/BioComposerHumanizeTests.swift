// BioComposerHumanizeTests.swift
// Echoel — H3 wiring (PLAN_HARMONY_CORE.md): HRV-humanize into BioComposer.
//
// Pins the laws of the slice:
//   • GOLDEN: `Input.humanize` defaults to false and the false path is the legacy
//     path — compose() output is byte-identical with the field omitted, with it
//     explicitly false, and across repeated calls (determinism).
//   • ZERO-JITTER: humanize ON with hrvNormalized 0 is IDENTICAL to OFF — the
//     jitter amplitude is the body's real HRV, so a rigid heart adds nothing.
//   • BOUNDED: humanize ON with real HRV deviates velocities, but every note
//     stays within ±(hrv · hrvHumanizeDepth) of the OFF velocity (clamped to
//     the musical [0.05, 1] window) — micro-variability, never swing.
//   • VELOCITY-ONLY (Slice 1): pitch, ticks (timing), role, drums untouched —
//     the live trigger clock is step-quantized, so a timing offset waits for
//     the sub-step clock slice.

import XCTest
@testable import Echoelmusic

final class BioComposerHumanizeTests: XCTestCase {

    private func input(style: MusicStyle = .jazz,
                       hrvNormalized: Float = 0.5,
                       seed: UInt64 = 0x5EED,
                       humanize: Bool = false) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: 70, hrvNormalized: hrvNormalized, coherence: 0.5,
                          breathPhase: 0, breathDepth: 0.5,
                          key: MusicalKey(root: 0, scale: .minor),
                          style: style, mode: .studioLocked, lockedTempo: 100,
                          seed: seed, humanize: humanize)
    }

    // MARK: - Golden: default-false is the legacy path, byte-identical

    func testHumanizeOff_matchesLegacyPath() {
        // The new field default-false changes NOTHING: an Input built without
        // naming it equals one with an explicit `humanize: false`, note for
        // note, across genre archetypes (block chords, signature beat, Fläche).
        for style in [MusicStyle.jazz, .dubTechno, .stillMeditation] {
            let defaulted = BioComposer.Input(heartRateBPM: 70, hrvNormalized: 0.5,
                                              coherence: 0.5, breathPhase: 0, breathDepth: 0.5,
                                              key: MusicalKey(root: 0, scale: .minor),
                                              style: style, mode: .studioLocked,
                                              lockedTempo: 100, seed: 0x5EED)
            let explicit = input(style: style, humanize: false)
            XCTAssertEqual(BioComposer.compose(defaulted), BioComposer.compose(explicit),
                           "\(style): default humanize must equal explicit false (legacy path)")
        }
    }

    func testGolden_sameInputComposesIdenticallyTwice() {
        // Determinism pin around the new field: the same Input (humanize
        // omitted → false) must reproduce the identical composition.
        let a = BioComposer.compose(input())
        let b = BioComposer.compose(input())
        XCTAssertEqual(a, b, "compose must stay deterministic with the H3 field present")
    }

    // MARK: - The zero-jitter law: hrv 0 ⇒ ON is identical to OFF

    func testHumanizeOn_zeroHRV_isIdenticalToOff() {
        for style in [MusicStyle.jazz, .dubTechno, .stillMeditation] {
            let off = BioComposer.compose(input(style: style, hrvNormalized: 0, humanize: false))
            let on = BioComposer.compose(input(style: style, hrvNormalized: 0, humanize: true))
            XCTAssertEqual(off, on,
                           "\(style): hrv 0 must add EXACTLY zero jitter — the amplitude IS the body")
        }
    }

    // MARK: - ON: deterministic

    func testHumanizeOn_isDeterministic() {
        let a = BioComposer.compose(input(hrvNormalized: 0.8, humanize: true))
        let b = BioComposer.compose(input(hrvNormalized: 0.8, humanize: true))
        XCTAssertEqual(a, b, "the HRV-humanized path must be seed-deterministic too")
    }

    // MARK: - ON: velocities deviate, but bounded by the hrv-scaled depth

    func testHumanizeOn_velocitiesDeviateWithinDepth() {
        let hrv: Float = 0.8
        let span = hrv * BioComposer.hrvHumanizeDepth
        let off = BioComposer.compose(input(hrvNormalized: hrv, humanize: false))
        let on = BioComposer.compose(input(hrvNormalized: hrv, humanize: true))

        XCTAssertEqual(off.notes.count, on.notes.count, "H3 must not add or drop notes")
        XCTAssertNotEqual(off.notes.map(\.velocity), on.notes.map(\.velocity),
                          "with real HRV the switch must actually loosen velocities")

        for (a, b) in zip(off.notes, on.notes) {
            // Bounded: b = clamp(a · (1 + v·span), 0.05, 1) with v ∈ [-1, 1], so the
            // ON velocity sits within the hrv-scaled window around the OFF velocity
            // (the 0.05 floor can only RAISE the lower edge, never widen it).
            XCTAssertGreaterThanOrEqual(b.velocity + 1e-5, a.velocity * (1 - span),
                                        "velocity must not drop below −span of the OFF value")
            XCTAssertLessThanOrEqual(b.velocity - 1e-5, Swift.min(1, a.velocity * (1 + span)),
                                     "velocity must not rise above +span of the OFF value")
            XCTAssertTrue((0...1).contains(b.velocity), "velocity must stay normalized")
            XCTAssertGreaterThanOrEqual(b.velocity, 0.05, "musical floor must hold")
        }
    }

    // MARK: - Slice 1 is velocity-only: pitch / timing / role / drums untouched

    func testHumanizeOn_touchesOnlyVelocity() {
        for style in [MusicStyle.jazz, .dubTechno, .stillMeditation] {
            let off = BioComposer.compose(input(style: style, hrvNormalized: 0.9, humanize: false))
            let on = BioComposer.compose(input(style: style, hrvNormalized: 0.9, humanize: true))
            XCTAssertEqual(off.notes.count, on.notes.count)
            for (a, b) in zip(off.notes, on.notes) {
                XCTAssertEqual(a.id, b.id, "\(style): note identity must be preserved")
                XCTAssertEqual(a.pitch, b.pitch, "\(style): pitches must be untouched")
                XCTAssertEqual(a.startTick, b.startTick, "\(style): timing must be untouched")
                XCTAssertEqual(a.lengthTicks, b.lengthTicks, "\(style): lengths must be untouched")
                XCTAssertEqual(a.role, b.role, "\(style): roles must be untouched")
            }
            XCTAssertEqual(off.drumSteps, on.drumSteps, "\(style): drums must be untouched")
            XCTAssertEqual(off.drumAccents, on.drumAccents, "\(style): accents must be untouched")
            XCTAssertEqual(off.suggestedTempo, on.suggestedTempo, "\(style): tempo must be untouched")
        }
    }

    // MARK: - The pure core law, directly

    func testHrvHumanize_coreLaws() {
        let notes = [Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 0.5),
                     Note(pitch: 64, startStep: 4, lengthSteps: 4, velocity: 0.5),
                     Note(pitch: 67, startStep: 8, lengthSteps: 4, velocity: 0.5)]

        // hrv 0 ⇒ the identical array back, untouched.
        XCTAssertEqual(BioComposer.hrvHumanize(notes, hrvNormalized: 0, seed: 1), notes)

        // Deterministic per (seed, index); a different seed gives a different feel.
        let a = BioComposer.hrvHumanize(notes, hrvNormalized: 1, seed: 1)
        let b = BioComposer.hrvHumanize(notes, hrvNormalized: 1, seed: 1)
        let c = BioComposer.hrvHumanize(notes, hrvNormalized: 1, seed: 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a.map(\.velocity), c.map(\.velocity))

        // Per-note independence: equal input velocities land on DIFFERENT jittered
        // values (each note draws its own derived stream — no uniform offset).
        XCTAssertNotEqual(a[0].velocity, a[1].velocity)

        // Amplitude law: jitter scales with hrv (half the hrv ⇒ half the swing).
        let full = BioComposer.hrvHumanize(notes, hrvNormalized: 1, seed: 1)
        let half = BioComposer.hrvHumanize(notes, hrvNormalized: 0.5, seed: 1)
        for (f, h) in zip(full, half) {
            let devFull = abs(f.velocity - 0.5)
            let devHalf = abs(h.velocity - 0.5)
            XCTAssertEqual(devHalf, devFull / 2, accuracy: 1e-5,
                           "jitter amplitude must be linear in hrv (same per-note draw)")
        }
    }
}
