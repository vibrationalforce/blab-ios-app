// BioEventSourceSwitchTests.swift
// Echoel — #186 follow-up: the cross-source phantom breath.
//
// ONE long-lived `BioEventGraph` sees frames from every source, and its detectors are
// edge-triggered on the PREVIOUS sample. `BreathPhaseDetector` fires inhale on
// `previous < 0.5 && phase >= 0.5`. So a camera session ending mid-cycle at 0.3, followed
// by the first HealthKit frame (whose `breathPhase` is a constant 0.5 placeholder), fired
// one inhale onset belonging to NEITHER source — an edge between two unrelated bodies of
// data, reported as a breath. `BioEventPublisher.tick` now calls `graph.reset()` when
// `frame.source` changes.
//
// ⛔ SCOPE, stated up front (the last two cycles both shipped a header that claimed more
// than it pinned): these tests exercise `BioEventGraph`'s RESET SEMANTICS — the property
// the fix relies on — NOT the publisher's wiring. `BioEventPublisher.tick` is private and
// driven by a 10 Hz `Task` against a live bus, so "the publisher calls reset on a source
// change" is not asserted here. Deleting the `if frame.source != lastSource` block would
// leave this file green. What it does buy: if `reset()` ever stopped clearing breath
// state, the fix would become a silent no-op, and THAT is caught here.
//
// `BioEventGraph` is a PROTECTED Rausch component. This file only CALLS its public API
// (`process`, `reset`) — the fix is caller-side, exactly as its SKILL.md prescribes.

import XCTest
@testable import Echoelmusic

final class BioEventSourceSwitchTests: XCTestCase {

    /// Feed one frame's worth of channels, returning whatever the graph emitted.
    private func feed(_ graph: inout BioEventGraph,
                      phase: Float,
                      at t: TimeInterval) -> [BioEvent] {
        graph.process(cleanedHeart: 0, breathPhase: phase, motionEnergy: 0, timestamp: t)
    }

    func testWithoutReset_aRisingEdgeAcrossTwoSourcesFiresAPhantomInhale() {
        // THE BUG, reproduced. This is the falsifiability half: it proves the edge really
        // does fire, so the test below is not passing for some unrelated reason.
        var graph = BioEventGraph(sampleRate: 10)
        _ = feed(&graph, phase: 0.3, at: 1)          // camera session ends mid-cycle
        let events = feed(&graph, phase: 0.5, at: 2) // first frame of the NEXT source
        XCTAssertTrue(events.contains { $0.kind == .breathInhaleOnset },
                      "0.3 → 0.5 crosses the inhale rule; without a reset this fires")
    }

    func testResetBetweenSources_suppressesThePhantomInhale() {
        // THE FIX's load-bearing property: after `reset()`, `previous` is invalid again,
        // so the first sample of the new source establishes a baseline instead of being
        // read as the far side of an edge.
        var graph = BioEventGraph(sampleRate: 10)
        _ = feed(&graph, phase: 0.3, at: 1)
        graph.reset()                                 // what tick() now does on a switch
        let events = feed(&graph, phase: 0.5, at: 2)
        XCTAssertFalse(events.contains { $0.kind == .breathInhaleOnset },
                       "the first frame after a source switch must not be an edge")
    }

    func testResetDoesNotDeafenTheDetector_realBreathingStillFires() {
        // The failure mode of an over-eager fix: reset on every frame would suppress
        // EVERY breath event and the bug report would become "no breath events at all".
        // One reset, then a genuine cycle within the new source, must still be detected.
        var graph = BioEventGraph(sampleRate: 10)
        graph.reset()
        _ = feed(&graph, phase: 0.2, at: 1)           // baseline sample after the switch
        let events = feed(&graph, phase: 0.6, at: 2)  // a real rising edge, same source
        XCTAssertTrue(events.contains { $0.kind == .breathInhaleOnset },
                      "after re-establishing a baseline, real breathing is detected again")
    }

    func testResetAlsoClearsTheExhaleEdge() {
        // Exhale is the other rule (`previous > 0.8 && phase < 0.2`) and has its own
        // stale-`previous` exposure — a camera session ending high, then a new source
        // starting low. Pinned separately so a partial reset cannot pass.
        var graph = BioEventGraph(sampleRate: 10)
        _ = feed(&graph, phase: 0.9, at: 1)
        graph.reset()
        let events = feed(&graph, phase: 0.1, at: 2)
        XCTAssertFalse(events.contains { $0.kind == .breathExhaleOnset })

        // And the same edge WITHOUT a reset does fire — again so the assertion above is
        // not vacuously true.
        var unreset = BioEventGraph(sampleRate: 10)
        _ = feed(&unreset, phase: 0.9, at: 1)
        let fired = feed(&unreset, phase: 0.1, at: 2)
        XCTAssertTrue(fired.contains { $0.kind == .breathExhaleOnset })
    }

    func testGraphEventsAreUnstampedSoTheEgressGateStaysFailClosed() {
        // Ties this fix to #186: whatever the graph emits carries no provenance, so if the
        // publisher's stamping were ever removed these events would be REFUSED at the OSC
        // drain rather than sent with an unknown origin.
        var graph = BioEventGraph(sampleRate: 10)
        _ = feed(&graph, phase: 0.3, at: 1)
        let events = feed(&graph, phase: 0.5, at: 2)
        XCTAssertFalse(events.isEmpty, "precondition: the graph emitted something to check")
        for e in events {
            XCTAssertNil(e.source)
            XCTAssertFalse(BioEgressPolicy.allowsEgress(e))
        }
    }
}
