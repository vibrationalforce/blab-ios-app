// ModulationEngineOutputsTests.swift
// REIHENFOLGE item 2 (Bio-Modulation live sichtbar): pins ModulationEngine's
// `lastOutputs` snapshot — the data spine a live "which parameter is the body
// moving, and by how much" leaf view reads. Ties the snapshot to the ACTUALLY
// dispatched value (via a capturing handler) so it never assumes the mapping.

import XCTest
@testable import Echoelmusic

@MainActor
final class ModulationEngineOutputsTests: XCTestCase {

    private func frame(coh: Float = 0.5, hr: Float = 120, ts: TimeInterval = 0) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: ts, heartRateBPM: hr, hrvNormalized: 0.5,
            breathRate: 12, breathPhase: 0.5, coherence: coh,
            motionEnergy: 0.5, source: .fallback
        )
    }

    private func route(_ source: ModSource, _ key: String) -> ModRoute {
        ModRoute(source: source, destination: ModDestination(key))
    }

    // MARK: - snapshot reflects applied outputs

    func testLastOutputs_matchesDispatchedValue() {
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "seq.tempo")]))
        var dispatched: Float?
        engine.register("seq.tempo") { dispatched = $0 }

        engine.apply(frame(coh: 1.0))

        let dest = ModDestination("seq.tempo")
        XCTAssertNotNil(dispatched)
        XCTAssertEqual(engine.lastOutputs[dest], dispatched,
                       "the live snapshot must equal what was dispatched")
    }

    func testLastOutputs_emptyWithNoRoutes() {
        let engine = ModulationEngine()
        engine.apply(frame(coh: 1.0))
        XCTAssertTrue(engine.lastOutputs.isEmpty)
    }

    func testLastOutputs_clearsWhenNothingMoves() {
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "seq.tempo")]))
        engine.apply(frame(coh: 1.0, ts: 0))
        XCTAssertFalse(engine.lastOutputs.isEmpty, "precondition: a route produced output")

        // Coherence 0 → zero output → skipped → result empty → snapshot clears,
        // so the item-2 meter doesn't freeze on a stale value when bio settles.
        engine.apply(frame(coh: 0.0, ts: 1))
        XCTAssertTrue(engine.lastOutputs.isEmpty)
    }

    // MARK: - ordered accessor

    func testOrderedOutputs_sortedByDestinationKey() {
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [
            route(.coherence, "b.tempo"),
            route(.coherence, "a.gain")
        ]))
        engine.apply(frame(coh: 1.0))

        let keys = engine.orderedOutputs.map { $0.destination.key }
        XCTAssertEqual(keys, ["a.gain", "b.tempo"], "a dict has no order; the accessor sorts by key")
    }

    // MARK: - lifecycle

    func testStop_clearsLastOutputs() {
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "seq.tempo")]))
        engine.apply(frame(coh: 1.0))
        XCTAssertFalse(engine.lastOutputs.isEmpty)

        engine.stop()
        XCTAssertTrue(engine.lastOutputs.isEmpty, "the meter clears when modulation stops")
    }

    // MARK: - re-apply stability (value correct on repeat)
    // NOTE: the internal `if lastOutputs != result` dedup that avoids re-notifying
    // observers on an idle tick is a perf guard verified by inspection, not here —
    // asserting non-reassignment would need withObservationTracking (Observation is
    // #if canImport-guarded in the engine, so it's kept out of this Linux-CI test).

    func testLastOutputs_stableAcrossRepeatedApply() {
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "seq.tempo")]))
        engine.apply(frame(coh: 0.7, ts: 0))
        let first = engine.lastOutputs
        engine.apply(frame(coh: 0.7, ts: 1))
        XCTAssertEqual(engine.lastOutputs, first, "same inputs → same snapshot")
    }
}
