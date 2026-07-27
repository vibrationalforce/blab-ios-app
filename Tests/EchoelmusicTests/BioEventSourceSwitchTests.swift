// BioEventSourceSwitchTests.swift
// Echoel — #186 follow-up: the phantom breath that belonged to no source.
//
// `BioEventGraph`'s breath detector is edge-triggered on the PREVIOUS sample (inhale on
// `previous < 0.5 && phase >= 0.5`). Feeding TWO sources into ONE graph therefore produces
// edges spanning both — a camera session ending mid-cycle at 0.3 followed by a HealthKit
// frame at 0.5 reads as an inhale that happened in neither body of data.
//
// ⛔ THE FIRST FIX WAS WORSE, and that is why this file has two layers of test.
// It reset the shared graph whenever `frame.source` changed. Review showed sources do NOT
// take turns: `stopBioSource` stops camera/strap/demo but not `HealthKitBioPublisher`,
// which starts at the first bio use of every run and keeps publishing alongside whatever
// the user picked. The bus interleaves, so reset-on-change would have fired twice per
// HealthKit sample and destroyed real camera breath edges. The fix is now PER-SOURCE
// detector state, which removes the class instead of trading one artifact for another.
//
// Layer 1 pins `BioEventGraph`'s reset semantics (the property the stale-gap path relies
// on). Layer 2 pins the PUBLISHER WIRING — driving `tick` directly, the seam
// `HealthKitBioPublisher.publishIfFresh(to:)` already established. The previous version of
// this file claimed the wiring was not pinnable; it was, one file away.
//
// `BioEventGraph` is a PROTECTED Rausch component. Only its public API is called.

import XCTest
@testable import Echoelmusic

final class BioEventSourceSwitchTests: XCTestCase {

    // MARK: - Layer 1: the graph's reset semantics

    private func feed(_ graph: inout BioEventGraph, phase: Float, at t: TimeInterval) -> [BioEvent] {
        graph.process(cleanedHeart: 0, breathPhase: phase, motionEnergy: 0, timestamp: t)
    }

    func testGraph_risingEdgeWithoutReset_firesInhale() {
        // Falsifiability half: proves the edge really does fire, so the suppression test
        // below is not passing for some unrelated reason.
        var graph = BioEventGraph(sampleRate: 10)
        _ = feed(&graph, phase: 0.3, at: 1)
        let events = feed(&graph, phase: 0.5, at: 2)
        XCTAssertTrue(events.contains { $0.kind == .breathInhaleOnset })
    }

    func testGraph_resetBeforeTheEdge_suppressesInhale() {
        var graph = BioEventGraph(sampleRate: 10)
        _ = feed(&graph, phase: 0.3, at: 1)
        graph.reset()
        let events = feed(&graph, phase: 0.5, at: 2)
        XCTAssertFalse(events.contains { $0.kind == .breathInhaleOnset })
    }

    func testGraph_resetDoesNotDeafenIt_realBreathingStillFires() {
        // Guards the opposite failure: a reset that suppressed everything would turn this
        // into "no breath events at all".
        var graph = BioEventGraph(sampleRate: 10)
        graph.reset()
        _ = feed(&graph, phase: 0.2, at: 1)
        let events = feed(&graph, phase: 0.6, at: 2)
        XCTAssertTrue(events.contains { $0.kind == .breathInhaleOnset })
    }

    func testGraph_resetClearsTheExhaleEdgeToo() {
        // Exhale is the other rule and has its own stale-`previous` exposure; pinned
        // separately so a partial reset cannot pass. Paired with its unreset twin.
        var graph = BioEventGraph(sampleRate: 10)
        _ = feed(&graph, phase: 0.9, at: 1)
        graph.reset()
        XCTAssertFalse(feed(&graph, phase: 0.1, at: 2).contains { $0.kind == .breathExhaleOnset })

        var unreset = BioEventGraph(sampleRate: 10)
        _ = feed(&unreset, phase: 0.9, at: 1)
        XCTAssertTrue(feed(&unreset, phase: 0.1, at: 2).contains { $0.kind == .breathExhaleOnset })
    }

    // MARK: - Layer 2: the publisher wiring (this is what the fix actually changed)

    @MainActor
    private func frame(_ source: BioSource, phase: Float, at t: TimeInterval) -> BioSampleFrame {
        BioSampleFrame(timestamp: t, heartRateBPM: 60, hrvNormalized: 0.5,
                       breathRate: 12, breathPhase: phase, coherence: 0.5,
                       motionEnergy: 0, source: source)
    }

    /// Publish a frame and drive exactly one `tick` against it.
    ///
    /// ⚠️ The await is NOT a sleep and is not optional: `EngineBus.publish(bio:)` is
    /// `nonisolated` and assigns `latestBio` inside a `Task { @MainActor }`, so the frame is
    /// NOT visible synchronously after publishing. Ticking straight away would read the
    /// PREVIOUS frame (or nil), and every assertion here would be measuring the wrong thing —
    /// the two tests expecting one event would fail for a reason that has nothing to do with
    /// per-source state. Yield until the snapshot is the frame we just published; this is the
    /// pattern `HealthKitBioPublisherTests.awaitLatestBio` already established, tightened to
    /// match on `timestamp` because after the first frame `latestBio` is never nil again.
    @MainActor
    private func step(_ publisher: BioEventPublisher, _ bus: EngineBus,
                      _ f: BioSampleFrame, tries: Int = 100) async {
        bus.publish(bio: f)
        for _ in 0..<tries {
            if bus.latestBio?.timestamp == f.timestamp { break }
            await Task.yield()
        }
        XCTAssertEqual(bus.latestBio?.timestamp, f.timestamp,
                       "frame at \(f.timestamp) never reached the bus snapshot — the tick below would test nothing")
        publisher.tick(bus)
    }

    @MainActor
    func testPublisher_interleavedSources_doNotCreateACrossSourceBreath() async {
        // THE BUG, at the layer it lives. Camera walks 0.1 → 0.3 (no edge of its own),
        // then a HealthKit frame arrives at its constant 0.5. With one shared graph that
        // 0.3 → 0.5 step is an inhale; with per-source state neither source has crossed
        // anything, so nothing may be published.
        let bus = EngineBus()
        let publisher = BioEventPublisher()
        await step(publisher, bus, frame(.cameraPPG, phase: 0.1, at: 1))
        await step(publisher, bus, frame(.cameraPPG, phase: 0.3, at: 2))
        await step(publisher, bus, frame(.healthKit, phase: 0.5, at: 3))
        XCTAssertEqual(publisher.eventsPublished, 0,
                       "an edge spanning two sources is not a breath in either of them")
    }

    @MainActor
    func testPublisher_interleavingDoesNotSwallowARealBreath() async {
        // The regression the FIRST fix would have caused: with reset-on-source-change, the
        // HealthKit frame in the middle wipes the camera's baseline and its genuine
        // 0.2 → 0.7 crossing is lost. Per-source state keeps it.
        let bus = EngineBus()
        let publisher = BioEventPublisher()
        await step(publisher, bus, frame(.cameraPPG, phase: 0.2, at: 1))
        await step(publisher, bus, frame(.healthKit, phase: 0.5, at: 2))
        await step(publisher, bus, frame(.cameraPPG, phase: 0.7, at: 3))
        XCTAssertEqual(publisher.eventsPublished, 1,
                       "the camera's own rising edge survives a frame from another source")
    }

    @MainActor
    func testPublisher_longGapInOneSource_clearsOnlyThatSourcesState() async {
        // Camera stalls (the documented 68–200 s rPPG freeze) and resumes. Its stored
        // `previous` describes a breath from minutes ago, so the resume must not be read
        // as an edge — while a second source's state is untouched.
        let bus = EngineBus()
        let publisher = BioEventPublisher()
        await step(publisher, bus, frame(.cameraPPG, phase: 0.2, at: 1))
        await step(publisher, bus, frame(.healthKit, phase: 0.5, at: 2))
        await step(publisher, bus, frame(.cameraPPG, phase: 0.7, at: 200))   // resume after a stall
        XCTAssertEqual(publisher.eventsPublished, 0,
                       "a resume after a long silence establishes a baseline, not an edge")
    }

    @MainActor
    func testPublisher_stampsProvenanceSoTheEgressGateCanDecide() async {
        // Ties back to #186: the graph cannot know where a frame came from, so if this
        // stamping were removed the event would be REFUSED at the OSC drain (fail-closed)
        // rather than sent with an unknown origin.
        let bus = EngineBus()
        let publisher = BioEventPublisher()
        await step(publisher, bus, frame(.cameraPPG, phase: 0.2, at: 1))
        await step(publisher, bus, frame(.cameraPPG, phase: 0.7, at: 2))
        XCTAssertEqual(publisher.eventsPublished, 1)
        let published = bus.bioEvents.dequeue()
        XCTAssertEqual(published?.source, .cameraPPG)
        XCTAssertEqual(published.map { BioEgressPolicy.allowsEgress($0) }, true)
    }
}
