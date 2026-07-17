//
//  BioBridgePayloadTests.swift
//  Echoelmusic — App-Group-Puls-Brücke (main app → AUv3 in third-party hosts)
//
//  Covers the shared BioVitals codec: roundtrip with the 2026-07-17 bridge
//  fields, backward-compatible decode of v1 payloads, the freshness gate the
//  AUv3 read side applies, NaN/∞ hardening, and the producer's frame→payload
//  mapping including the BioEgressPolicy (5.1.3) rule.
//

import XCTest
@testable import Echoelmusic

final class BioBridgePayloadTests: XCTestCase {

    private func suite() -> String { "BioBridgeTests.\(UUID().uuidString)" }

    // MARK: - Codec roundtrip (incl. breathRate + egressAllowed)

    func testRoundTrip_carriesBreathRateAndEgressFlag() throws {
        let v = BioVitals(heartRateBPM: 62, hrvNormalized: 0.4, breathPhase: 0.75,
                          coherence: 0.9, timestamp: 123.5,
                          breathRate: 5.5, egressAllowed: true)
        let decoded = try JSONDecoder().decode(BioVitals.self, from: JSONEncoder().encode(v))
        XCTAssertEqual(decoded, v)
        XCTAssertTrue(decoded.egressAllowed)
        XCTAssertEqual(decoded.breathRate, 5.5)
    }

    // MARK: - v1 payload compatibility (old app writes, new extension reads)

    func testDecode_legacyV1Payload_defaultsToNonEgressAndZeroBreathRate() throws {
        // Exactly the fields a pre-2026-07-17 build wrote under "bioVitals.v1".
        let legacy = Data("""
        {"heartRateBPM":80,"hrvNormalized":0.5,"breathPhase":0.25,"coherence":0.6,"timestamp":42}
        """.utf8)
        let v = try JSONDecoder().decode(BioVitals.self, from: legacy)
        XCTAssertEqual(v.heartRateBPM, 80)
        XCTAssertEqual(v.timestamp, 42)
        // Unmarked old payload may be HealthKit-sourced ⇒ never host-visible.
        XCTAssertFalse(v.egressAllowed)
        XCTAssertEqual(v.breathRate, 0)
    }

    // MARK: - Freshness gate (the AUv3 read side, ~2 s window)

    func testIsFresh_boundaries() {
        let v = BioVitals(timestamp: 100)
        XCTAssertTrue(v.isFresh(within: 2, now: 100))      // same instant
        XCTAssertTrue(v.isFresh(within: 2, now: 102))      // exactly at the window
        XCTAssertFalse(v.isFresh(within: 2, now: 102.01))  // just past ⇒ stale
        XCTAssertTrue(v.isFresh(within: 2, now: 99.5))     // ≤1 s clock jitter tolerated
        XCTAssertFalse(v.isFresh(within: 2, now: 98.5))    // >1 s from the future ⇒ reject
    }

    func testIsFresh_defaultZeroTimestamp_isStale() {
        XCTAssertFalse(BioVitals().isFresh())
    }

    // MARK: - NaN/∞ hardening

    func testPayloadIsFinite_flagsEveryNonFiniteField() {
        XCTAssertTrue(BioVitals(timestamp: 1).payloadIsFinite)
        XCTAssertFalse(BioVitals(heartRateBPM: .nan, timestamp: 1).payloadIsFinite)
        XCTAssertFalse(BioVitals(hrvNormalized: .infinity, timestamp: 1).payloadIsFinite)
        XCTAssertFalse(BioVitals(breathPhase: .nan, timestamp: 1).payloadIsFinite)
        XCTAssertFalse(BioVitals(coherence: -.infinity, timestamp: 1).payloadIsFinite)
        XCTAssertFalse(BioVitals(timestamp: .nan).payloadIsFinite)
        XCTAssertFalse(BioVitals(timestamp: 1, breathRate: .nan).payloadIsFinite)
    }

    func testPublish_nonFiniteVitals_neverReachesTheStore() {
        let s = suite(); defer { UserDefaults().removePersistentDomain(forName: s) }
        let mgr = BioFeedbackManager(appGroup: s)
        // JSONEncoder rejects non-finite floats ⇒ publish is a no-op, and the
        // consumer keeps returning nil instead of a poisoned frame.
        mgr.publish(BioVitals(heartRateBPM: .nan, timestamp: 1))
        XCTAssertNil(mgr.refreshFromSharedStore())
    }

    // MARK: - Producer mapping (BioSampleFrame → BioVitals) incl. 5.1.3 egress

    private func frame(source: BioSource) -> BioSampleFrame {
        BioSampleFrame(timestamp: 7, heartRateBPM: 70, hrvNormalized: 0.3,
                       breathRate: 6, breathPhase: 0.5, coherence: 0.8,
                       motionEnergy: 0, source: source)
    }

    func testVitalsFromFrame_copiesChannelsAndTimestamp() {
        let v = BioFeedbackPublisher.vitals(from: frame(source: .ble))
        XCTAssertEqual(v.heartRateBPM, 70)
        XCTAssertEqual(v.hrvNormalized, 0.3)
        XCTAssertEqual(v.breathRate, 6)
        XCTAssertEqual(v.breathPhase, 0.5)
        XCTAssertEqual(v.coherence, 0.8)
        XCTAssertEqual(v.timestamp, 7)
    }

    func testVitalsFromFrame_egressMatchesBioEgressPolicy() {
        // Own measurements (camera / strap / demo) may surface in host-visible
        // AUParameters; HealthKit-store-derived sources never (5.1.3) — the
        // exact same split OSCSender enforces.
        for source in [BioSource.ble, .cameraPPG, .fallback] {
            XCTAssertTrue(BioFeedbackPublisher.vitals(from: frame(source: source)).egressAllowed,
                          "expected egress for \(source)")
        }
        for source in [BioSource.healthKit, .watch, .oura] {
            XCTAssertFalse(BioFeedbackPublisher.vitals(from: frame(source: source)).egressAllowed,
                           "expected NO egress for \(source)")
        }
    }
}
