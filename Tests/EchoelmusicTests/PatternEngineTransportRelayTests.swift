// PatternEngineTransportRelayTests.swift
// Echoel — Cycle 1 of Transport unification: PatternEngine keeps its own timer but
// RELAYS tempo / swing / play / stop into the authoritative Transport. These are
// Foundation-only types (no AVFoundation/Accelerate), so this file is UNGATED and
// ci.yml EXECUTES it on Linux — unlike TransportTests, which are AVFoundation-gated
// and therefore only compiled, never run.

import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class PatternEngineTransportRelayTests: XCTestCase {

    func testTempo_relaysToTransport() {
        let pattern = PatternEngine()
        let transport = Transport()
        pattern.transport = transport
        pattern.setTempo(140)
        XCTAssertEqual(transport.tempo, 140, accuracy: 1e-9)
        // Clamped values relay clamped, not raw.
        pattern.setTempo(9_999)
        XCTAssertEqual(transport.tempo, Transport.maxTempo, accuracy: 1e-9)
    }

    func testSwing_relaysToTransport() {
        let pattern = PatternEngine()
        let transport = Transport()
        pattern.transport = transport
        pattern.setSwing(0.3)
        XCTAssertEqual(transport.swing, 0.3, accuracy: 1e-9)
        pattern.setSwing(9)   // clamped to 0.5
        XCTAssertEqual(transport.swing, 0.5, accuracy: 1e-9)
    }

    func testPlayStop_relayPlayStateToTransport() {
        let pattern = PatternEngine()
        let transport = Transport()
        pattern.transport = transport
        pattern.play()
        XCTAssertTrue(transport.isPlaying)
        pattern.stop()
        XCTAssertFalse(transport.isPlaying)
        XCTAssertEqual(transport.position, .zero)
        pattern.stop()   // cancel the real timer source so it cannot fire after teardown
    }

    // MARK: - The seam the click now depends on

    func testTempoReachesASubscriberThroughTheRelay() {
        // ONE BPM: the metronome no longer gets pushed its tempo from the UI, it
        // subscribes to the Transport. That makes THIS seam — sequencer tempo →
        // relay → subscriber — load-bearing for whether the click moves at all.
        // Testing Transport's subscriber list alone cannot catch a missing relay
        // (or a missing `pattern.transport = transport` at startup); this can.
        let pattern = PatternEngine()
        let transport = Transport()
        pattern.transport = transport
        var seen: [Double] = []
        transport.onTempoChange(id: "click") { seen.append($0) }
        seen.removeAll()                       // drop the immediate seed
        pattern.setTempo(140)
        XCTAssertEqual(seen, [140])
    }

    func testSameValueSetTempo_stillRelays_soAMirrorCanReSync() {
        // `setTempo` relays BEFORE its `guard clamped != tempo` early return, on
        // purpose: if Transport ever diverged, a same-value edit must re-sync it.
        // The early return sits right below the relay, so this ordering is one
        // line-move away from being lost.
        let pattern = PatternEngine()
        let transport = Transport()
        pattern.setTempo(140)                  // pattern moves while NOT attached
        pattern.transport = transport          // transport still at its default
        XCTAssertNotEqual(transport.tempo, 140, accuracy: 1e-9)
        pattern.setTempo(140)                  // same value for the pattern — a no-op edit
        XCTAssertEqual(transport.tempo, 140, accuracy: 1e-9)
    }

    func testNoTransport_isHarmlessNoOp() {
        // The relay is optional: a PatternEngine with no Transport attached must
        // behave exactly as before (no crash, normal tempo/swing state).
        let pattern = PatternEngine()
        pattern.setTempo(150)
        pattern.setSwing(0.25)
        XCTAssertEqual(pattern.tempo, 150, accuracy: 1e-9)
        XCTAssertEqual(pattern.swing, 0.25, accuracy: 1e-9)
    }

    // MARK: - Play cause (#175): the diagnostic must not become behavior

    /// `play(cause:)` exists so a device log can name WHICH of the seven call sites
    /// started the transport. It must stay purely diagnostic: every cause has to leave
    /// the engine and the relayed Transport in exactly the state a bare `play()` does.
    func testPlayCause_doesNotChangeBehaviour() {
        for cause in [PatternEngine.PlayCause.transportButton, .generate, .pianoRoll,
                      .arrangement, .timelineRegion, .launchQuantized, .loopExport,
                      .unspecified] {
            let pattern = PatternEngine()
            let transport = Transport()
            pattern.transport = transport
            pattern.play(cause: cause)
            XCTAssertTrue(pattern.isPlaying, "\(cause.rawValue) must start the clock")
            XCTAssertTrue(transport.isPlaying, "\(cause.rawValue) must relay to Transport")
            XCTAssertEqual(pattern.currentStep, 0, "\(cause.rawValue) must start from step 0")
            pattern.play(cause: cause)   // idempotent: a second call changes nothing
            XCTAssertTrue(pattern.isPlaying)
            pattern.stop()               // cancel the real timer before teardown
            XCTAssertFalse(pattern.isPlaying)
        }
    }

    /// The rawValues are what a founder's `echoel_diag.log` is grepped for, so they are
    /// part of the diagnostic contract: renaming one silently breaks log reading of
    /// every build shipped before the rename. Distinctness matters for the same reason —
    /// two causes sharing a string would make the log unable to tell them apart.
    func testPlayCauseRawValues_areStableAndDistinct() {
        let expected: [PatternEngine.PlayCause: String] = [
            .transportButton: "transportButton",
            .generate:        "generate",
            .pianoRoll:       "pianoRoll",
            .arrangement:     "arrangement",
            .timelineRegion:  "timelineRegion",
            .launchQuantized: "launchQuantized",
            .loopExport:      "loopExport",
            .unspecified:     "unspecified",
        ]
        for (cause, raw) in expected {
            XCTAssertEqual(cause.rawValue, raw)
        }
        XCTAssertEqual(Set(expected.values).count, expected.count, "rawValues must be distinct")
    }
}
