// BioTempoDirectorTests.swift
// Echoel — the bio-tempo lane model (founder "BPM both"). Guards: locked ignores the body;
// bio-follow glides toward the heartbeat, pulled toward resonance by coherence; the glide
// never lurches and always stays in the musical tempo band.

import XCTest
@testable import Echoelmusic

final class BioTempoDirectorTests: XCTestCase {

    // MARK: locked mode

    func testLocked_ignoresBody() {
        let d = BioTempoDirector(mode: .locked, lockedTempo: 124)
        XCTAssertEqual(d.targetTempo(heartRateBPM: 180, coherence: 0), 124, accuracy: 1e-9)
        XCTAssertEqual(d.targetTempo(heartRateBPM: 45, coherence: 1), 124, accuracy: 1e-9)
        // Even mid-glide it converges to the locked value, not the pulse.
        XCTAssertEqual(d.nextTempo(previous: 124, heartRateBPM: 180, coherence: 0, dt: 1),
                       124, accuracy: 1e-9)
    }

    // MARK: bio-follow mode

    func testBioFollow_targetIsHeartRateAtZeroCoherence() {
        let d = BioTempoDirector(mode: .bioFollow, lockedTempo: 120)
        XCTAssertEqual(d.targetTempo(heartRateBPM: 96, coherence: 0), 96, accuracy: 1e-9,
                       "no coherence → the target is the raw heartbeat")
    }

    func testBioFollow_coherencePullsTowardResonance() {
        let d = BioTempoDirector(mode: .bioFollow)
        let hr = 120.0
        let none = d.targetTempo(heartRateBPM: hr, coherence: 0)
        let mid  = d.targetTempo(heartRateBPM: hr, coherence: 0.5)
        let full = d.targetTempo(heartRateBPM: hr, coherence: 1)
        XCTAssertEqual(none, 120, accuracy: 1e-9)
        XCTAssertEqual(full, BioTempoDirector.resonanceBPM, accuracy: 1e-9,
                       "full coherence converges to the resonance band")
        XCTAssertLessThan(mid, none, "coherence draws the racing pulse down")
        XCTAssertGreaterThan(mid, full)
    }

    func testBioFollow_zeroHeartRateFallsBackToLocked() {
        let d = BioTempoDirector(mode: .bioFollow, lockedTempo: 128)
        XCTAssertEqual(d.targetTempo(heartRateBPM: 0, coherence: 0), 128, accuracy: 1e-9,
                       "no pulse yet → hold the locked tempo, don't collapse to the floor")
    }

    // MARK: glide behaviour

    func testGlide_movesTowardTargetButNotPast() {
        let d = BioTempoDirector(mode: .bioFollow, lockedTempo: 90, glideSeconds: 4)
        let next = d.nextTempo(previous: 90, heartRateBPM: 150, coherence: 0, dt: 1)
        XCTAssertGreaterThan(next, 90, "glides up toward the faster pulse")
        XCTAssertLessThan(next, 150, "one step does not jump all the way (no lurch)")
    }

    func testGlide_convergesOverManySteps() {
        let d = BioTempoDirector(mode: .bioFollow, lockedTempo: 90, glideSeconds: 2)
        var t = 90.0
        for _ in 0..<200 { t = d.nextTempo(previous: t, heartRateBPM: 140, coherence: 0, dt: 0.1) }
        XCTAssertEqual(t, 140, accuracy: 0.5, "converges to the target heartbeat over time")
    }

    func testGlide_zeroDtOrZeroGlideSnaps() {
        let snap = BioTempoDirector(mode: .bioFollow, glideSeconds: 0)
        XCTAssertEqual(snap.nextTempo(previous: 90, heartRateBPM: 130, coherence: 0, dt: 1),
                       130, accuracy: 1e-9, "zero glide snaps to target")
        let d = BioTempoDirector(mode: .bioFollow, glideSeconds: 4)
        XCTAssertEqual(d.nextTempo(previous: 90, heartRateBPM: 130, coherence: 0, dt: 0),
                       130, accuracy: 1e-9, "zero dt snaps to target")
    }

    // MARK: safety + persistence

    func testTempoStaysInMusicalBand() {
        let d = BioTempoDirector(mode: .bioFollow)
        XCTAssertLessThanOrEqual(d.targetTempo(heartRateBPM: 9999, coherence: 0),
                                 BioTempoDirector.maxTempo)
        XCTAssertGreaterThanOrEqual(d.targetTempo(heartRateBPM: 1, coherence: 0),
                                    BioTempoDirector.minTempo)
        XCTAssertEqual(d.nextTempo(previous: .nan, heartRateBPM: 120, coherence: 0, dt: 1)
                        .isFinite, true, "a NaN previous never propagates")
    }

    func testCodableRoundTrip() throws {
        let d = BioTempoDirector(mode: .bioFollow, lockedTempo: 132, glideSeconds: 3)
        let back = try JSONDecoder().decode(BioTempoDirector.self,
                                            from: try JSONEncoder().encode(d))
        XCTAssertEqual(back, d)
    }
}
