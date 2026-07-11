// BioComposerDynamicsTests.swift
// Echoel — bar-internal dynamic SHAPE (Cycle M1). The device clip measured LRA 1.7 LU
// (dynamically dead — a flat 1-bar loop). `barDynamic`/`shapeBarDynamics` give the loop
// musical phrasing (metric accent + swell) so the whole texture breathes. Pure → tested here.

import XCTest
@testable import Echoelmusic

final class BioComposerDynamicsTests: XCTestCase {

    typealias C = BioComposer
    private let steps = BioComposer.stepCount

    // MARK: - barDynamic (the pure multiplier)

    func testBarDynamic_theOneIsTheLoudestEventInTheBar() {
        // Founder law ("die Eins zu erkennen"): the bar's ONE (step 0) must be the
        // strongest event — louder than mid-bar (step 8) and any weak 16th (step 15) —
        // so the ear anchors to the downbeat every bar.
        let one  = C.barDynamic(step: 0, stepCount: steps, depth: 0.6)
        let mid  = C.barDynamic(step: 8, stepCount: steps, depth: 0.6)
        let weak = C.barDynamic(step: 15, stepCount: steps, depth: 0.6)
        XCTAssertGreaterThan(one, mid)   // the one now wins over mid-bar (was reversed)
        XCTAssertGreaterThan(one, weak)
        XCTAssertGreaterThan(mid, weak)
    }

    func testBarDynamic_metricHierarchy_beatOverEighthOverSixteenth() {
        // At the same swell neighbourhood, beat (step 4) > 8th (step 6) > 16th (step 5).
        let beat    = C.barDynamic(step: 4, stepCount: steps, depth: 0.6)
        let eighth  = C.barDynamic(step: 6, stepCount: steps, depth: 0.6)
        let sixteen = C.barDynamic(step: 5, stepCount: steps, depth: 0.6)
        XCTAssertGreaterThan(beat, sixteen)
        XCTAssertGreaterThan(eighth, sixteen)
    }

    func testBarDynamic_centeredNearOne_andBounded() {
        // Across the whole bar the multiplier stays within [1-depth/2, 1+depth/2].
        let depth: Float = 0.6
        for s in 0..<steps {
            let m = C.barDynamic(step: s, stepCount: steps, depth: depth)
            XCTAssertGreaterThanOrEqual(m, 1 - depth / 2 - 0.001)
            XCTAssertLessThanOrEqual(m, 1 + depth / 2 + 0.001)
        }
    }

    func testBarDynamic_depthZero_isNoOp() {
        for s in 0..<steps {
            XCTAssertEqual(C.barDynamic(step: s, stepCount: steps, depth: 0), 1, accuracy: 0.0001)
        }
    }

    func testBarDynamic_stepWrapsByBar() {
        XCTAssertEqual(C.barDynamic(step: 0, stepCount: steps, depth: 0.6),
                       C.barDynamic(step: steps, stepCount: steps, depth: 0.6), accuracy: 0.0001)
    }

    // MARK: - shapeBarDynamics (applied to a take)

    private func note(_ step: Int, vel: Float = 0.6) -> Note {
        Note(pitch: 60, startStep: step, lengthSteps: 1, velocity: vel)
    }

    func testShape_increasesDynamicSpread_onAFlatTake() {
        // A flat take (every note velocity 0.6, spread across the bar) must gain real
        // dynamic spread — the whole point of the fix (LRA 1.7 was ~zero spread).
        let flat = (0..<steps).map { note($0, vel: 0.6) }
        let shaped = C.shapeBarDynamics(flat, depth: 0.6, stepCount: steps)
        let vs = shaped.map { $0.velocity }
        let spread = (vs.max() ?? 0) - (vs.min() ?? 0)
        XCTAssertGreaterThan(spread, 0.2)   // was 0 before shaping
    }

    func testShape_depthZero_leavesVelocitiesUnchanged() {
        let flat = (0..<steps).map { note($0, vel: 0.6) }
        let shaped = C.shapeBarDynamics(flat, depth: 0, stepCount: steps)
        for (a, b) in zip(flat, shaped) { XCTAssertEqual(a.velocity, b.velocity, accuracy: 0.0001) }
    }

    func testShape_clampsToMusicalWindow() {
        // Extreme inputs stay inside [0.05, 1] so nothing silences or clips.
        let hot = [note(8, vel: 0.98)]          // mid-bar downbeat, boosted
        let quiet = [note(15, vel: 0.06)]       // weak offbeat, cut
        let sHot = C.shapeBarDynamics(hot, depth: 0.6, stepCount: steps)[0].velocity
        let sQuiet = C.shapeBarDynamics(quiet, depth: 0.6, stepCount: steps)[0].velocity
        XCTAssertLessThanOrEqual(sHot, 1.0)
        XCTAssertGreaterThanOrEqual(sQuiet, 0.05)
    }

    func testShape_isDeterministic() {
        let take = (0..<steps).map { note($0, vel: 0.5) }
        let a = C.shapeBarDynamics(take, depth: 0.6, stepCount: steps).map { $0.velocity }
        let b = C.shapeBarDynamics(take, depth: 0.6, stepCount: steps).map { $0.velocity }
        XCTAssertEqual(a, b)
    }

    // MARK: - End-to-end: a composed take is no longer velocity-flat

    func testComposedTake_hasDynamicVariation() {
        let input = BioComposer.Input(heartRateBPM: 72, coherence: 0.5,
                                      key: MusicalKey(root: 0, scale: .minor),
                                      style: .dubTechno, mode: .studioLocked, lockedTempo: 124)
        let take = BioComposer.compose(input)
        let vs = take.notes.map { $0.velocity }
        guard vs.count > 1 else { return }   // nothing to assert on a 1-note take
        let spread = (vs.max() ?? 0) - (vs.min() ?? 0)
        XCTAssertGreaterThan(spread, 0.05, "composed take should carry audible dynamics, not a flat velocity")
    }
}
