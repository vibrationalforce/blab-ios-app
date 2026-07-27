// BioEgressPolicyTests.swift
// Echoelmusic — App Store 5.1.3: HealthKit-store data never leaves the device.
// The OSC/ADM senders forward only Echoel-measured sources; this pins the rule.

import XCTest
@testable import Echoelmusic

final class BioEgressPolicyTests: XCTestCase {

    func testOwnMeasurements_mayStreamOffDevice() {
        XCTAssertTrue(BioEgressPolicy.allowsEgress(.cameraPPG), "camera rPPG is Echoel's own measurement")
        XCTAssertTrue(BioEgressPolicy.allowsEgress(.ble), "BLE strap is Echoel's own measurement")
        XCTAssertTrue(BioEgressPolicy.allowsEgress(.fallback), "demo generator carries no real health data")
        // faceCam is measured on-device like rPPG; only abstracted [0..1] expression
        // channels egress, never the image.
        XCTAssertTrue(BioEgressPolicy.allowsEgress(.faceCam), "face expression is Echoel's own on-device measurement")
    }

    func testHealthKitStoreSources_neverStreamOffDevice() {
        // 5.1.3: anything read out of the HealthKit store (or bridges that route
        // through it) stays on the device — a user-typed UDP host could be anywhere.
        XCTAssertFalse(BioEgressPolicy.allowsEgress(.healthKit))
        XCTAssertFalse(BioEgressPolicy.allowsEgress(.watch))
        XCTAssertFalse(BioEgressPolicy.allowsEgress(.oura))
    }

    func testEverySourceHasAnExplicitRuling() {
        // A new BioSource case must consciously pick a side (the switch in the
        // policy is exhaustive; this documents the full current census).
        let all: [BioSource] = [.fallback, .healthKit, .oura, .ble, .watch, .cameraPPG, .faceCam]
        for source in all {
            _ = BioEgressPolicy.allowsEgress(source)   // must not trap; compile-time exhaustive
        }
        XCTAssertEqual(all.count, 7, "update this census when BioSource grows")
    }
}

// MARK: - #186: the EVENT path obeys the same rule as the frame path

/// The gap this pins was real and shipped: `OSCSender.sendIfFresh` refused a
/// HealthKit/Watch FRAME while `drainAndSendEvents` sent the breath and motion ONSETS
/// derived from that very frame, because `BioEvent` carried no provenance and the drain
/// had no guard. The policy file's own header even declared the event path exempt.
///
/// These tests are about the DECISION, which is where the rule lives — the drain is a
/// `private func` on a `@MainActor` class that owns a live `NWConnection`, so asserting
/// "no UDP packet left" is not something this suite can do honestly. What it CAN pin is
/// the provenance contract that decision reads: that events carry a source, that the
/// protected graph's unstamped output stays unstamped, and that unstamped fails CLOSED.
final class BioEventEgressTests: XCTestCase {

    private func event(_ source: BioSource?) -> BioEvent {
        BioEvent(timestamp: 1, kind: .breathInhaleOnset, confidence: 1, aux: 0, source: source)
    }

    /// The exact expression `drainAndSendEvents` guards on. Kept in one place so the test
    /// and the call site cannot drift into disagreeing about what "allowed" means.
    private func mayEgress(_ e: BioEvent) -> Bool {
        guard let s = e.source else { return false }
        return BioEgressPolicy.allowsEgress(s)
    }

    func testUnstampedEvent_isRefused_failClosed() {
        // The whole safety argument rests on this direction. `BioEventGraph` is protected
        // and cannot stamp; a producer that forgets to stamp must go SILENT, never leak.
        XCTAssertFalse(mayEgress(event(nil)))
    }

    func testHealthDerivedOnset_isRefused_eventhoughItsChannelsAreDerived() {
        // The failure mode in one line: a HealthKit frame carries a real breathRate /
        // breathPhase from the Health store, so an onset derived from it is Health-derived
        // — even though a graph, not the store, computed the onset.
        XCTAssertFalse(mayEgress(event(.healthKit)))
        XCTAssertFalse(mayEgress(event(.watch)))
        XCTAssertFalse(mayEgress(event(.oura)))
    }

    func testOwnMeasuredOnset_isAllowed_soTheGateIsNotJustAnOffSwitch() {
        // Falsifiability: without this, "refuse everything" would pass every test above
        // and the gate would be indistinguishable from deleting the feature.
        XCTAssertTrue(mayEgress(event(.ble)))
        XCTAssertTrue(mayEgress(event(.cameraPPG)))
        XCTAssertTrue(mayEgress(event(.fallback)))
        XCTAssertTrue(mayEgress(event(.faceCam)))
    }

    func testStampedPreservesEverythingElse() {
        // `stamped(source:)` exists so the PROTECTED graph's output can gain provenance
        // without the graph being edited. It must change provenance and nothing else — a
        // stamp that quietly rounded a timestamp would corrupt event timing downstream.
        let raw = BioEvent(timestamp: 12.5, kind: .heartbeat, confidence: 0.75, aux: 812)
        XCTAssertNil(raw.source, "the graph produces unstamped events by construction")
        let stamped = raw.stamped(source: .ble)
        XCTAssertEqual(stamped.source, .ble)
        XCTAssertEqual(stamped.timestamp, 12.5, accuracy: 1e-9)
        XCTAssertEqual(stamped.kind, .heartbeat)
        XCTAssertEqual(stamped.confidence, 0.75, accuracy: 1e-6)
        XCTAssertEqual(stamped.aux, 812, accuracy: 1e-6)
    }

    func testDefaultInitLeavesEventsUnstamped() {
        // Pins the DEFAULT, which is the load-bearing half of fail-closed: `BioEventGraph`
        // calls the 4-argument init, so if that default ever became a permissive source
        // every graph-derived event would start egressing silently.
        let fromGraph = BioEvent(timestamp: 0, kind: .motionPeak, confidence: 1, aux: 0)
        XCTAssertNil(fromGraph.source)
        XCTAssertFalse(mayEgress(fromGraph))
    }
}
