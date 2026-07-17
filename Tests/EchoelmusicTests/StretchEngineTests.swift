// StretchEngineTests.swift
// Echoelmusic — Sequencer tests
//
// Pure coverage for the Echoel stretch-engine spine: the mode enum's character laws +
// honest fallback, and the StretchPlan resolver (rate + pitch-preservation).

import XCTest
@testable import Echoelmusic

final class StretchEngineTests: XCTestCase {

    // MARK: - StretchMode character laws

    func testPreservesPitch_onlyTapeMovesPitch() {
        XCTAssertTrue(StretchMode.clean.preservesPitch)
        XCTAssertTrue(StretchMode.beats.preservesPitch)
        XCTAssertTrue(StretchMode.studio.preservesPitch)
        XCTAssertFalse(StretchMode.tape.preservesPitch)
    }

    func testIsImplemented_cleanTapeAndBeats() {
        XCTAssertTrue(StretchMode.clean.isImplemented)
        XCTAssertTrue(StretchMode.tape.isImplemented)   // tape = pitch-follows-tempo, wired
        XCTAssertTrue(StretchMode.beats.isImplemented)  // WSOLA pre-render (editor preview)
        XCTAssertFalse(StretchMode.studio.isImplemented)
    }

    func testEffectiveMode_baseFallback_keepsTimelineHonest() {
        XCTAssertEqual(StretchMode.clean.effectiveMode, .clean)
        XCTAssertEqual(StretchMode.tape.effectiveMode, .tape)    // base-capable → itself
        // Beats IS implemented, but only the preview consumer executes it — the
        // BASE fallback (what resolve's default renders) stays .clean so the
        // timeline never claims a character it can't render.
        XCTAssertEqual(StretchMode.beats.effectiveMode, .clean)
        XCTAssertEqual(StretchMode.studio.effectiveMode, .clean)
    }

    func testSelectable_offersBeats() {
        XCTAssertEqual(StretchMode.selectable, [.clean, .tape, .beats])
    }

    // MARK: - Per-consumer capabilities (#54 Beats preview)

    func testResolve_defaultCapabilities_rendersBeatsAsClean() {
        let plan = StretchPlan.resolve(mode: .beats, warpEnabled: true,
                                       nativeBPM: 120, projectBPM: 140)
        XCTAssertEqual(plan.mode, .clean, "timeline consumers keep the honest fallback")
        XCTAssertTrue(plan.preservesPitch)
    }

    func testResolve_previewCapabilities_rendersBeats() {
        let plan = StretchPlan.resolve(mode: .beats, warpEnabled: true,
                                       nativeBPM: 120, projectBPM: 140,
                                       capabilities: StretchMode.previewCapabilities)
        XCTAssertEqual(plan.mode, .beats)
        XCTAssertTrue(plan.preservesPitch, "WSOLA holds pitch")
        XCTAssertEqual(plan.rate, 140.0 / 120.0, accuracy: 1e-9)
        // Studio stays gated even for the preview consumer.
        let studio = StretchPlan.resolve(mode: .studio, warpEnabled: true,
                                         nativeBPM: 120, projectBPM: 140,
                                         capabilities: StretchMode.previewCapabilities)
        XCTAssertEqual(studio.mode, .clean)
    }

    func testCodable_roundTripsViaRawValue() throws {
        for mode in StretchMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let back = try JSONDecoder().decode(StretchMode.self, from: data)
            XCTAssertEqual(back, mode)
        }
    }

    // MARK: - StretchPlan resolver

    func testResolve_warpOff_rateIsUnity() {
        let plan = StretchPlan.resolve(mode: .clean, warpEnabled: false,
                                       nativeBPM: 120, projectBPM: 140)
        XCTAssertEqual(plan.rate, 1.0, accuracy: 1e-9)
        XCTAssertTrue(plan.preservesPitch)
        XCTAssertEqual(plan.mode, .clean)
    }

    func testResolve_warpOn_rateMatchesTempoMatch() {
        let plan = StretchPlan.resolve(mode: .clean, warpEnabled: true,
                                       nativeBPM: 120, projectBPM: 140)
        // 140 / 120 = 1.16667, inside the 0.25…4.0 clamp.
        XCTAssertEqual(plan.rate, 140.0 / 120.0, accuracy: 1e-9)
        XCTAssertEqual(plan.rate, TempoMatch.stretchRate(nativeBPM: 120, masterBPM: 140), accuracy: 1e-12)
    }

    func testResolve_unknownNativeOrZeroProject_rateUnity() {
        XCTAssertEqual(StretchPlan.resolve(mode: .clean, warpEnabled: true,
                                           nativeBPM: 0, projectBPM: 140).rate, 1.0, accuracy: 1e-9)
        XCTAssertEqual(StretchPlan.resolve(mode: .clean, warpEnabled: true,
                                           nativeBPM: 120, projectBPM: 0).rate, 1.0, accuracy: 1e-9)
    }

    func testResolve_unimplementedMode_rendersAsCleanPitchPreserved() {
        // A `.beats` selection today has no executor → renders as `.clean` (pitch preserved),
        // never silent, never a lying selector. The rate still tempo-conforms.
        let plan = StretchPlan.resolve(mode: .beats, warpEnabled: true,
                                       nativeBPM: 100, projectBPM: 120)
        XCTAssertEqual(plan.mode, .clean)
        XCTAssertTrue(plan.preservesPitch)
        XCTAssertEqual(plan.rate, 120.0 / 100.0, accuracy: 1e-9)
    }

    func testResolve_tapeMode_pitchMovesWithTempo() {
        // Tape is implemented → renders as itself, pitch NOT preserved (rides tempo).
        let plan = StretchPlan.resolve(mode: .tape, warpEnabled: true,
                                       nativeBPM: 100, projectBPM: 120)
        XCTAssertEqual(plan.mode, .tape)
        XCTAssertFalse(plan.preservesPitch)
        XCTAssertEqual(plan.rate, 1.2, accuracy: 1e-9)
    }

    // MARK: - Tape pitch-follows-tempo math

    func testTapePitchCents_unityRate_isZero() {
        XCTAssertEqual(StretchPlan.tapePitchCents(forRate: 1.0), 0, accuracy: 1e-9)
    }

    func testTapePitchCents_octaveUp_is1200() {
        // rate 2.0 = one octave faster → +1200 cents (pitch rides tempo, like tape).
        XCTAssertEqual(StretchPlan.tapePitchCents(forRate: 2.0), 1200, accuracy: 1e-6)
    }

    func testTapePitchCents_octaveDown_isMinus1200() {
        XCTAssertEqual(StretchPlan.tapePitchCents(forRate: 0.5), -1200, accuracy: 1e-6)
    }

    func testTapePitchCents_nonPositiveRate_isZero() {
        XCTAssertEqual(StretchPlan.tapePitchCents(forRate: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(StretchPlan.tapePitchCents(forRate: -1), 0, accuracy: 1e-9)
    }

    func testResolve_matchesRegionEffectiveStretchRate() {
        // The plan's rate must never diverge from AudioClipRegion.effectiveStretchRate.
        let region = AudioClipRegion(startSeconds: 0, endSeconds: 4, warpEnabled: true,
                                     nativeBPM: 90, stretchMode: .clean)
        let plan = StretchPlan.resolve(mode: region.stretchMode, warpEnabled: region.warpEnabled,
                                       nativeBPM: region.nativeBPM, projectBPM: 128)
        XCTAssertEqual(plan.rate, region.effectiveStretchRate(projectBPM: 128), accuracy: 1e-12)
    }

    // MARK: - AudioClipRegion persistence

    func testRegion_defaultsToCleanMode() {
        XCTAssertEqual(AudioClipRegion().stretchMode, .clean)
    }

    func testRegion_decodeWithoutStretchMode_defaultsClean() throws {
        // A region persisted before the engine existed (no stretchMode key) loads clean.
        let legacy = #"{"startSeconds":0,"endSeconds":2,"loop":false,"gain":1,"fadeInSeconds":0,"fadeOutSeconds":0,"warpEnabled":true,"nativeBPM":120}"#
        let region = try JSONDecoder().decode(AudioClipRegion.self, from: Data(legacy.utf8))
        XCTAssertEqual(region.stretchMode, .clean)
        XCTAssertTrue(region.warpEnabled)
        XCTAssertEqual(region.nativeBPM, 120, accuracy: 1e-9)
    }

    func testRegion_stretchModeRoundTrips() throws {
        let region = AudioClipRegion(startSeconds: 0, endSeconds: 3, warpEnabled: true,
                                     nativeBPM: 128, stretchMode: .tape)
        let data = try JSONEncoder().encode(region)
        let back = try JSONDecoder().decode(AudioClipRegion.self, from: data)
        XCTAssertEqual(back.stretchMode, .tape)
    }
}
