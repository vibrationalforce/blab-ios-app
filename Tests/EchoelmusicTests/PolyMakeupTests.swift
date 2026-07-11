// PolyMakeupTests.swift
// Echoel — the smoothed poly makeup gain (EchoelPolyDDSP.polyMakeupTarget /
// .smoothedMakeup). Guards Ralph-Zyklus 2 "Polyphonie-Headroom" (founder
// 2026-07-11: "EchoelSynth rudimentär bei den Levels · Einzelnote voll, Akkord
// zerrt nicht"): a single note must play near-FULL while a dense chord is backed
// off along a 1/√N law — and the change from note to note must EASE, never jump
// (the old raw per-block 1/√N pumped, which is why smoothing is mandatory).
// Pure functions → fully unit-testable, no AVAudio / Accelerate render needed.

#if canImport(Accelerate)
import XCTest
@testable import Echoelmusic

final class PolyMakeupTests: XCTestCase {

    private typealias Poly = EchoelPolyDDSP

    func testSingleNoteIsNearFull() {
        // One voice must play at the full single-voice gain — NOT the old thin 0.40.
        let g = Poly.polyMakeupTarget(voiceCount: 1)
        XCTAssertGreaterThan(g, 0.8, "a single note must sound full, well above the old 0.40")
    }

    func testZeroOrNegativeVoicesClampToFull() {
        // Silence / a bad count must not divide-by-zero or blow up — treated as 1 voice.
        XCTAssertEqual(Poly.polyMakeupTarget(voiceCount: 0), Poly.polyMakeupTarget(voiceCount: 1))
        XCTAssertEqual(Poly.polyMakeupTarget(voiceCount: -5), Poly.polyMakeupTarget(voiceCount: 1))
    }

    func testDenseChordIsBackedOff() {
        // More voices → lower makeup, so the coherent sum is tamed before the tanh.
        let one = Poly.polyMakeupTarget(voiceCount: 1)
        let four = Poly.polyMakeupTarget(voiceCount: 4)
        let twelve = Poly.polyMakeupTarget(voiceCount: 12)
        XCTAssertGreaterThan(one, four, "a chord is quieter per-voice than a single note")
        XCTAssertGreaterThan(four, twelve, "a denser chord is backed off further")
    }

    func testFollowsInverseSqrtLaw() {
        // Quadrupling the voice count halves the gain (1/√N), until the floor clamps.
        let one = Poly.polyMakeupTarget(voiceCount: 1)
        let four = Poly.polyMakeupTarget(voiceCount: 4)
        XCTAssertEqual(four, one / 2, accuracy: 0.01, "1/√N: 4 voices ≈ half the single-note gain")
    }

    func testNeverBelowTheFloor() {
        // Even a pathological voice count stays at/above the safety floor (no silence,
        // no negative gain).
        let g = Poly.polyMakeupTarget(voiceCount: 64)
        XCTAssertGreaterThanOrEqual(g, 0.22, "makeup never collapses below the floor")
    }

    func testSmoothingEasesGraduallyNotInOneJump() {
        // Going from a full single note (0.85) to a dense-chord target must move only a
        // FRACTION of the way in one block — this is the anti-pump property.
        let target = Poly.polyMakeupTarget(voiceCount: 12)   // ~0.245, well below 0.85
        let step = Poly.smoothedMakeup(current: 0.85, target: target, coeff: 0.04)
        XCTAssertLessThan(step, 0.85, "it moves toward the chord target")
        XCTAssertGreaterThan(step, target + 0.4, "but only a small fraction in one block (no jump)")
    }

    func testSmoothingConvergesToTarget() {
        // Held at a constant voice count, the smoothed gain converges to the target.
        let target = Poly.polyMakeupTarget(voiceCount: 3)
        var g: Float = 0.85
        for _ in 0..<2000 { g = Poly.smoothedMakeup(current: g, target: target, coeff: 0.04) }
        XCTAssertEqual(g, target, accuracy: 0.001, "settles exactly on the voice-count target")
    }

    func testSmoothingCoeffIsClamped() {
        // A coeff ≥ 1 snaps to target (never overshoots); ≤ 0 holds — both bounded.
        XCTAssertEqual(Poly.smoothedMakeup(current: 0.2, target: 0.85, coeff: 5), 0.85, accuracy: 1e-6)
        XCTAssertEqual(Poly.smoothedMakeup(current: 0.2, target: 0.85, coeff: -1), 0.2, accuracy: 1e-6)
    }
}
#endif
