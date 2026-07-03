// TempoStabilityTests.swift
// Echoel — encodes the "bpm springt nicht mehr" contracts (v10.79.37–79.42) as
// executable law. Two halves:
//   1. StudioCalculator.seedTempo — the octave-fold that stops a doubled rPPG pulse
//      (196 ≈ 2×98) from seeding a runaway beat.
//   2. PatternEngine.glideTempo — a body re-seed EASES the running beat instead of
//      snapping it; user edits (setTempo) stay instant and cancel any glide.
// Foundation-only types (no AVFoundation/SwiftUI), so this file is UNGATED and
// ci.yml EXECUTES it on Linux — the same rationale as PatternEngineTransportRelayTests.

import XCTest
import Foundation
@testable import Echoelmusic

final class SeedTempoTests: XCTestCase {

    func testDoubledPulse_foldsIntoMusicalRange() {
        // The founder's exact failure: a 196 bpm octave artifact must not set ~196.
        XCTAssertEqual(StudioCalculator.seedTempo(196), 98, accuracy: 1e-9)
        // Other 2× artifacts fold once…
        XCTAssertEqual(StudioCalculator.seedTempo(160), 80, accuracy: 1e-9)
        XCTAssertEqual(StudioCalculator.seedTempo(140), 70, accuracy: 1e-9)
        // …and an absurd runaway folds repeatedly until musical.
        XCTAssertEqual(StudioCalculator.seedTempo(1000), 125, accuracy: 1e-9)
    }

    func testRestingRange_passesThroughUnchanged() {
        // A genuine resting/seated body seed must NOT be altered.
        for bpm in [50.0, 63, 72, 84, 98, 110, 128, 130] {
            XCTAssertEqual(StudioCalculator.seedTempo(bpm), bpm, accuracy: 1e-9,
                           "resting seed \(bpm) must pass through")
        }
    }

    func testClampBounds() {
        // Below the playable floor → 50; the fold itself can land at most at 130.
        XCTAssertEqual(StudioCalculator.seedTempo(30), 50, accuracy: 1e-9)
        XCTAssertEqual(StudioCalculator.seedTempo(0), 50, accuracy: 1e-9)
        XCTAssertEqual(StudioCalculator.seedTempo(260), 130, accuracy: 1e-9)
    }
}

@MainActor
final class TempoGlideTests: XCTestCase {

    func testGlideWhileStopped_snapsImmediately() {
        // No ticks exist to ease on when the transport is stopped, so the glide
        // degrades to a precise instant set (initial generate must not lag).
        let pattern = PatternEngine()
        let transport = Transport()
        pattern.transport = transport
        pattern.glideTempo(to: 150)
        XCTAssertEqual(pattern.tempo, 150, accuracy: 1e-9)
        XCTAssertEqual(transport.tempo, 150, accuracy: 1e-9)   // relay intact
    }

    func testGlideWhileStopped_clamps() {
        let pattern = PatternEngine()
        pattern.glideTempo(to: 9_999)
        XCTAssertEqual(pattern.tempo, PatternEngine.maxTempo, accuracy: 1e-9)
    }

    func testGlideWhilePlaying_neverJumpsSynchronously() {
        // THE anti-jump contract: while the beat runs, a body re-seed must NOT move
        // the tempo in the same instant — advance() eases it tick by tick instead.
        let pattern = PatternEngine()
        pattern.play()
        let before = pattern.tempo
        pattern.glideTempo(to: before + 40)
        XCTAssertEqual(pattern.tempo, before, accuracy: 1e-9,
                       "glide must not snap the running beat")
        pattern.stop()   // cancel the real timer source before teardown
    }

    func testSetTempo_cancelsGlideAndWinsInstantly() {
        // A user edit is precise + instant — it overrides any in-flight body glide.
        let pattern = PatternEngine()
        pattern.play()
        pattern.glideTempo(to: 200)
        pattern.setTempo(100)
        XCTAssertEqual(pattern.tempo, 100, accuracy: 1e-9)
        pattern.stop()
    }

    func testStop_dropsGlideTarget() {
        // A stop mid-glide must not leave a stale target that yanks the NEXT take.
        let pattern = PatternEngine()
        pattern.play()
        let before = pattern.tempo
        pattern.glideTempo(to: before + 40)
        pattern.stop()
        XCTAssertEqual(pattern.tempo, before, accuracy: 1e-9,
                       "stopping mid-glide must freeze, not jump")
    }
}
