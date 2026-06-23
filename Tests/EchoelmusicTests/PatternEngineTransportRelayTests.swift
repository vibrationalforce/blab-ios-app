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

    func testNoTransport_isHarmlessNoOp() {
        // The relay is optional: a PatternEngine with no Transport attached must
        // behave exactly as before (no crash, normal tempo/swing state).
        let pattern = PatternEngine()
        pattern.setTempo(150)
        pattern.setSwing(0.25)
        XCTAssertEqual(pattern.tempo, 150, accuracy: 1e-9)
        XCTAssertEqual(pattern.swing, 0.25, accuracy: 1e-9)
    }
}
